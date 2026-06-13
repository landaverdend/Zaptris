use std::collections::HashMap;
use std::str::FromStr;
use std::sync::{mpsc, Arc, Mutex};
use std::time::Duration;
use nostr_sdk::prelude::*;
use nostr_sdk::nips::nip47::{
    LookupInvoiceRequestParams,
    MakeInvoiceRequestParams,
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

    /// Create a BOLT-11 invoice. Pass amount_sats=0 for an amountless invoice
    /// (payer chooses the amount — used for attack invoices).
    pub async fn create_invoice(&self, job_id: i64, amount_sats: u64, memo: &str) -> Result<String, String> {
        let params = MakeInvoiceRequestParams {
            amount:           amount_sats * 1000,
            description:      Some(memo.to_string()),
            description_hash: None,
            expiry:           Some(3600), // 1 hour — long enough for a full match
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
                            let amount_sats = resp.amount as i64;
                            eprintln!("[payments] invoice settled — job_id={job_id} amount={amount_sats}");
                            pending.lock().unwrap().remove(&hash);
                            tx.send(crate::BridgeEvent::InvoicePaid(job_id, amount_sats)).ok();
                        }
                        Ok(_)  => eprintln!("[payments] job_id={job_id} not yet settled"),
                        Err(e) => eprintln!("[payments] lookup error (job={job_id}): {e}"),
                    }
                }
            }
        });
    }
}

