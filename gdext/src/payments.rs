use std::collections::HashMap;
use std::str::FromStr;
use std::sync::{mpsc, Arc, Mutex};
use std::time::Duration;
use nostr_sdk::prelude::*;
use nostr_sdk::nips::nip47::{
    ListTransactionsRequestParams, LookupInvoiceRequestParams,
    MakeInvoiceRequestParams, TransactionType,
};

/// How long to wait between lookup_invoice polls for each pending invoice.
const WATCH_INTERVAL_SECS: u64 = 5;

/// payment_hash → opaque job_id
type PendingMap = Arc<Mutex<HashMap<String, i64>>>;

/// Owns the NWC connection. The tokio runtime is shared with RustBridge —
/// passed in at construction so the whole extension uses a single thread pool.
pub struct PaymentClient {
    nwc:            NWC,
    rt:             Arc<tokio::runtime::Runtime>,
    pending:        PendingMap,
}

impl PaymentClient {
    /// Initialise from a raw NWC URI string.
    pub fn new(nwc_string: &str, rt: Arc<tokio::runtime::Runtime>) -> Result<Self, String> {
        let uri = NostrWalletConnectURI::from_str(nwc_string.trim())
            .map_err(|e| format!("invalid NWC URI: {e}"))?;
        Ok(Self {
            nwc: NWC::new(uri),
            rt,
            pending: Arc::new(Mutex::new(HashMap::new())),
        })
    }

    /// Load HOST_NWC from the project-root .env file.
    pub fn from_env(rt: Arc<tokio::runtime::Runtime>) -> Result<Self, String> {
        dotenvy::dotenv().ok();
        let nwc_string = std::env::var("HOST_NWC")
            .map_err(|_| "HOST_NWC not set — add it to .env".to_string())?;
        Self::new(&nwc_string, rt)
    }

    /// Create a BOLT-11 invoice. Stores payment_hash → job_id for the watch loop.
    pub async fn create_invoice(&self, job_id: i64, amount_sats: u64, memo: &str) -> Result<String, String> {
        let params = MakeInvoiceRequestParams {
            amount:           amount_sats * 1_000, // NWC uses millisats
            description:      Some(memo.to_string()),
            description_hash: None,
            expiry:           Some(600),
        };
        let result = self.nwc.make_invoice(params).await
            .map_err(|e| format!("make_invoice: {e}"))?;
        self.pending.lock().unwrap().insert(result.payment_hash.clone(), job_id);
        Ok(result.invoice)
    }

    /// Pay a BOLT-11 invoice via NWC.
    pub async fn pay_invoice(&self, bolt11: &str) -> Result<(), String> {
        self.nwc.pay_invoice(bolt11).await
            .map_err(|e| format!("pay_invoice: {e}"))?;
        Ok(())
    }

    /// Poll list_transactions every 5 s for new settled incoming payments.
    /// Payments whose comment/description matches "PLAYER_IDX COMMAND" (e.g. "0 GARBAGE")
    /// are forwarded as BridgeEvent::ZapCommand — same event the game already handles.
    ///
    /// Uses LNURL-pay comments (metadata["comment"]) so any Lightning wallet works —
    /// no Nostr client required. Falls back to the invoice description field.
    pub fn start_watching_commands(&self, tx: mpsc::SyncSender<crate::BridgeEvent>) {
        let nwc = self.nwc.clone();
        self.rt.spawn(async move {
            // Only react to payments that arrive after startup.
            let mut since = Timestamp::now();
            // Dedup ring-buffer — protects against re-processing if Alby returns
            // the same invoice across two polls at a boundary timestamp.
            let mut seen = std::collections::HashSet::<String>::new();

            tx.send(crate::BridgeEvent::Log(
                "[payments] command watcher started (LNURL-pay comments)".into()
            )).ok();

            loop {
                tokio::time::sleep(Duration::from_secs(5)).await;

                let params = ListTransactionsRequestParams {
                    from:             Some(since),
                    until:            None,
                    limit:            Some(50),
                    offset:           None,
                    unpaid:           Some(false),
                    transaction_type: Some(TransactionType::Incoming),
                };

                let results = match nwc.list_transactions(params).await {
                    Ok(r)  => r,
                    Err(e) => {
                        tx.send(crate::BridgeEvent::Log(
                            format!("[payments] poll error: {e}")
                        )).ok();
                        continue;
                    }
                };

                for t in &results {
                    // Dedup: skip if we already processed this payment.
                    if !seen.insert(t.payment_hash.clone()) { continue; }

                    // Prefer the LNURL-pay comment; fall back to invoice description.
                    let raw = t.metadata
                        .as_ref()
                        .and_then(|v| v.as_object())
                        .and_then(|m| m.get("comment"))
                        .and_then(|v: &serde_json::Value| v.as_str())
                        .or_else(|| t.description.as_deref())
                        .unwrap_or("")
                        .trim();

                    if let Some((player_idx, command)) = parse_lnurl_command(raw) {
                        let sats = (t.amount / 1000) as i64;
                        tx.send(crate::BridgeEvent::Log(
                            format!("[payments] command: player={player_idx} {sats} sats  cmd={command}")
                        )).ok();
                        tx.send(crate::BridgeEvent::ZapCommand(player_idx, sats, command)).ok();
                    }
                }

                // Advance the window — but keep a 30-second lookback buffer so an
                // invoice that was created just before our window but settled after
                // it still gets caught on the next poll. The seen HashSet handles
                // dedup for anything that re-appears inside the buffer.
                let floor = Timestamp::now().as_u64().saturating_sub(30);
                if let Some(newest) = results.iter().map(|t| t.created_at.as_u64()).max() {
                    since = Timestamp::from(newest.saturating_add(1).max(floor));
                } else {
                    since = Timestamp::from(floor);
                }
            }
        });
    }

    /// Drop all pending invoice watches — call on lobby reset.
    pub fn clear_pending(&self) {
        self.pending.lock().unwrap().clear();
    }

    /// Spawn an async task on the shared runtime that polls lookup_invoice
    /// every WATCH_INTERVAL_SECS seconds. Settled invoices are pushed onto
    /// `tx` as BridgeEvent::InvoicePaid. No dedicated OS thread — runs on
    /// the tokio thread pool alongside the NWC calls.
    pub fn start_watching(&self, tx: mpsc::SyncSender<crate::BridgeEvent>) {
        let nwc     = self.nwc.clone();
        let pending = Arc::clone(&self.pending);

        self.rt.spawn(async move {
            eprintln!("[payments] watch task started");
            loop {
                tokio::time::sleep(Duration::from_secs(WATCH_INTERVAL_SECS)).await;

                let to_check: Vec<(String, i64)> = {
                    let map = pending.lock().unwrap();
                    if map.is_empty() { continue; }
                    map.iter().map(|(h, &id)| (h.clone(), id)).collect()
                };

                eprintln!("[payments] checking {} pending invoice(s)", to_check.len());

                for (hash, job_id) in to_check {
                    let params = LookupInvoiceRequestParams {
                        payment_hash: Some(hash.clone()),
                        invoice:      None,
                    };
                    match nwc.lookup_invoice(params).await {
                        Ok(resp) if resp.settled_at.is_some() => {
                            eprintln!("[payments] invoice settled — job_id={job_id}");
                            pending.lock().unwrap().remove(&hash);
                            tx.send(crate::BridgeEvent::InvoicePaid(job_id)).ok();
                        }
                        Ok(_)  => eprintln!("[payments] job_id={job_id} not yet settled"),
                        Err(e) => eprintln!("[payments] lookup error (job={job_id}): {e}"),
                    }
                }
            }
        });
    }
}

/// Parse a game command from a LNURL-pay comment or invoice description.
/// Expected format: "PLAYER_IDX COMMAND" e.g. "0 GARBAGE" or "1 NUKE".
/// Returns (player_index, UPPERCASE_COMMAND) or None if unrecognised.
fn parse_lnurl_command(s: &str) -> Option<(i64, String)> {
    let (idx_str, cmd) = s.trim().split_once(' ')?;
    let player_idx: i64 = idx_str.trim().parse().ok()?;
    let command = cmd.trim().to_uppercase();
    if command.is_empty() { return None; }
    Some((player_idx, command))
}

