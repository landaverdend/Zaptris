use godot::prelude::*;
use std::sync::{mpsc, Arc, Mutex};
use std::sync::atomic::{AtomicBool, Ordering};

mod lnurl;
mod payments;
mod qr;

struct StacktrisExtension;

#[gdextension]
unsafe impl ExtensionLibrary for StacktrisExtension {}

// ── Event bus ──────────────────────────────────────────────────────────────────
//
// All background work (NWC calls, HTTP, QR encoding) runs on the shared tokio
// runtime. Results are sent here; poll() drains the channel on the main thread
// and emits the corresponding Godot signals.

pub(crate) enum BridgeEvent {
    InvoiceReady(i64, Vec<u8>),        // player_index, PNG bytes
    InvoicePaid(i64, i64),             // player_index, amount_sats
    AddressChecked(i64, bool, String), // player_index, valid, message
    PaymentSettled(i64, bool),         // amount_sats, success
    Log(String),                       // diagnostic message → godot_print
}

// ── Bridge node ────────────────────────────────────────────────────────────────

#[derive(GodotClass)]
#[class(base=Node)]
pub struct RustBridge {
    base:           Base<Node>,
    /// Shared tokio runtime — one thread pool for the whole extension.
    rt:             Arc<tokio::runtime::Runtime>,
    payment_client: Option<Arc<payments::PaymentClient>>,
    tx:             mpsc::SyncSender<BridgeEvent>,
    rx:             Mutex<mpsc::Receiver<BridgeEvent>>,
    /// True while a pay_winner call is in flight — prevents overlapping payouts.
    paying:         Arc<AtomicBool>,
}

#[godot_api]
impl INode for RustBridge {
    fn init(base: Base<Node>) -> Self {
        let rt = Arc::new(
            tokio::runtime::Runtime::new().expect("tokio runtime"),
        );
        let (tx, rx) = mpsc::sync_channel(64);
        Self {
            base,
            rt,
            payment_client: None,
            tx,
            rx:     Mutex::new(rx),
            paying: Arc::new(AtomicBool::new(false)),
        }
    }

    fn ready(&mut self) {
        match payments::PaymentClient::from_env(Arc::clone(&self.rt)) {
            Ok(client) => {
                client.start_watching(self.tx.clone());
                self.payment_client = Some(Arc::new(client));
                godot_print!("[payments] NWC client ready");
            }
            Err(e) => godot_print!("[payments] no NWC client: {e}"),
        }
    }
}

#[godot_api]
impl RustBridge {

    // ── Queue drain (called by GDScript Timer every 1s) ───────────────────────

    #[func]
    fn poll(&mut self) {
        // Collect all pending events under the lock, then release it before
        // calling emit_signal (which needs &mut self).
        let events: Vec<BridgeEvent> = {
            let rx = self.rx.lock().unwrap();
            std::iter::from_fn(|| rx.try_recv().ok()).collect()
        };

        for event in events {
            match event {
                BridgeEvent::InvoiceReady(idx, bytes) => {
                    let ba = PackedByteArray::from(bytes.as_slice());
                    self.base_mut().emit_signal("invoice_ready", &[
                        idx.to_variant(), ba.to_variant(),
                    ]);
                }
                BridgeEvent::InvoicePaid(idx, amount_sats) => {
                    godot_print!("[payments] invoice_paid — player {idx} {amount_sats} sats");
                    self.base_mut().emit_signal("invoice_paid", &[
                        idx.to_variant(), amount_sats.to_variant(),
                    ]);
                }
                BridgeEvent::AddressChecked(idx, valid, msg) => {
                    self.base_mut().emit_signal("address_checked", &[
                        idx.to_variant(),
                        valid.to_variant(),
                        GString::from(msg).to_variant(),
                    ]);
                }
                BridgeEvent::PaymentSettled(amount, success) => {
                    self.base_mut().emit_signal("payment_settled", &[
                        amount.to_variant(), success.to_variant(),
                    ]);
                }
                BridgeEvent::Log(msg) => {
                    godot_print!("{msg}");
                }
            }
        }
    }

    // ── Payments ──────────────────────────────────────────────────────────────

    /// Request a fixed-amount buy-in invoice for a player.
    /// Emits `invoice_ready(player_index, qr_bytes)` on the next poll().
    #[func]
    fn create_player_invoice(&self, player_index: i64, amount_sats: i64) {
        let memo = format!("Zapstris buy-in P{}", player_index + 1);
        self.spawn_invoice(player_index, amount_sats as u64, memo);
    }

    /// Request a fixed-amount attack invoice for a player.
    /// Paying it sends `amount_sats` lines of garbage to that player.
    /// Emits `invoice_ready(player_index, qr_bytes)` on the next poll().
    #[func]
    fn create_attack_invoice(&self, player_index: i64, amount_sats: i64) {
        let memo = format!("Zapstris attack P{} ({} sats)", player_index + 1, amount_sats);
        self.spawn_invoice(player_index, amount_sats as u64, memo);
    }

    fn spawn_invoice(&self, player_index: i64, amount_sats: u64, memo: String) {
        let client = match &self.payment_client {
            Some(c) => Arc::clone(c),
            None => {
                godot_print!("[payments] NWC not configured — check HOST_NWC in .env");
                return;
            }
        };
        let tx = self.tx.clone();
        self.rt.spawn(async move {
            // The NWC relay websocket may not be connected yet right after
            // client initialisation. Retry a few times with a short delay
            // before giving up — the loading skeleton covers the wait.
            const MAX_ATTEMPTS: u32 = 5;
            const RETRY_MS:     u64 = 2_000;

            for attempt in 1..=MAX_ATTEMPTS {
                match client.create_invoice(player_index, amount_sats, &memo).await {
                    Ok(invoice) => {
                        tx.send(BridgeEvent::Log(format!(
                            "[payments] invoice ready player={player_index} len={}", invoice.len()
                        ))).ok();
                        let png = tokio::task::spawn_blocking(move || qr::generate_png(&invoice))
                            .await
                            .unwrap_or_else(|e| { eprintln!("[qr] panic: {e}"); Vec::new() });
                        tx.send(BridgeEvent::Log(format!(
                            "[payments] qr png bytes={}", png.len()
                        ))).ok();
                        tx.send(BridgeEvent::InvoiceReady(player_index, png)).ok();
                        return;
                    }
                    Err(e) => {
                        let retryable = e.contains("relay not connected")
                            || e.contains("not published")
                            || e.contains("status changed");
                        if retryable && attempt < MAX_ATTEMPTS {
                            tx.send(BridgeEvent::Log(format!(
                                "[payments] relay not ready, retrying player={player_index} \
                                 (attempt {attempt}/{MAX_ATTEMPTS}) in {RETRY_MS}ms…"
                            ))).ok();
                            tokio::time::sleep(tokio::time::Duration::from_millis(RETRY_MS)).await;
                        } else {
                            tx.send(BridgeEvent::Log(format!(
                                "[payments] invoice error player={player_index} \
                                 after {attempt} attempt(s): {e}"
                            ))).ok();
                        }
                    }
                }
            }
        });
    }

    #[func]
    fn clear_pending_invoices(&self) {
        if let Some(client) = &self.payment_client {
            client.clear_pending();
        }
    }

    // ── Lightning address validation ──────────────────────────────────────────

    /// Validate a Lightning address in the background.
    /// Emits `address_checked(player_index, is_valid, message)` on the next poll().
    #[func]
    fn check_lightning_address(&self, player_index: i64, address: GString) {
        let tx      = self.tx.clone();
        let address = address.to_string();

        // ureq is sync — run on the blocking thread pool so it doesn't
        // occupy an async worker while waiting on the socket.
        self.rt.spawn(async move {
            let result = tokio::task::spawn_blocking(move || lnurl::check_address(&address))
                .await
                .unwrap_or_else(|e| Err(e.to_string()));
            let (valid, msg) = match result {
                Ok(())   => (true,  "Reachable ✓".to_string()),
                Err(msg) => (false, msg),
            };
            tx.send(BridgeEvent::AddressChecked(player_index, valid, msg)).ok();
        });
    }

    // ── Payout ────────────────────────────────────────────────────────────────

    /// Pay `amount_sats` to a Lightning address.
    /// At most one payment runs at a time — skips if one is already in flight.
    /// Emits `payment_settled(amount, success)` on the next poll().
    #[func]
    fn pay_winner(&self, lightning_address: GString, amount_sats: i64) {
        if self.paying.compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst).is_err() {
            godot_print!("[payments] payment already in flight — skipping tick");
            return;
        }
        let client = match &self.payment_client {
            Some(c) => Arc::clone(c),
            None => {
                self.paying.store(false, Ordering::SeqCst);
                godot_print!("[payments] NWC not configured — cannot pay winner");
                return;
            }
        };
        let address = lightning_address.to_string();
        let paying  = Arc::clone(&self.paying);
        let tx      = self.tx.clone();

        self.rt.spawn(async move {
            // LNURL-pay fetch is sync HTTP — blocking pool.
            let fetch_addr  = address.clone();
            let bolt11_result = tokio::task::spawn_blocking(move || {
                lnurl::fetch_invoice(&fetch_addr, amount_sats as u64)
            })
            .await
            .unwrap_or_else(|e| Err(e.to_string()));

            let success = match bolt11_result {
                Ok(bolt11) => match client.pay_invoice(&bolt11).await {
                    Ok(())  => { eprintln!("[payments] paid {amount_sats} sats → {address}"); true }
                    Err(e)  => { eprintln!("[payments] pay_invoice failed: {e}"); false }
                },
                Err(e) => { eprintln!("[payments] fetch_invoice failed for {address}: {e}"); false }
            };

            paying.store(false, Ordering::SeqCst);
            tx.send(BridgeEvent::PaymentSettled(amount_sats, success)).ok();
        });
    }

    /// Pay the remaining pot to the match winner. Unlike pay_winner, this does
    /// not check the paying flag — the final payout should always go through
    /// even if a tick payment is still in flight.
    #[func]
    fn pay_pot_remainder(&self, lightning_address: GString, amount_sats: i64) {
        let client = match &self.payment_client {
            Some(c) => Arc::clone(c),
            None => {
                godot_print!("[payments] NWC not configured — cannot pay pot remainder");
                return;
            }
        };
        let address = lightning_address.to_string();
        let tx      = self.tx.clone();

        self.rt.spawn(async move {
            let fetch_addr    = address.clone();
            let bolt11_result = tokio::task::spawn_blocking(move || {
                lnurl::fetch_invoice(&fetch_addr, amount_sats as u64)
            })
            .await
            .unwrap_or_else(|e| Err(e.to_string()));

            let success = match bolt11_result {
                Ok(bolt11) => match client.pay_invoice(&bolt11).await {
                    Ok(())  => { eprintln!("[payments] pot remainder: {amount_sats} sats → {address}"); true }
                    Err(e)  => { eprintln!("[payments] pot remainder pay_invoice failed: {e}"); false }
                },
                Err(e) => { eprintln!("[payments] pot remainder fetch failed for {address}: {e}"); false }
            };
            tx.send(BridgeEvent::PaymentSettled(amount_sats, success)).ok();
        });
    }

    // ── QR ────────────────────────────────────────────────────────────────────

    #[func]
    fn generate_qr(&self, data: GString) -> PackedByteArray {
        qr::generate_qr(&data.to_string())
    }

    // ── Signals ───────────────────────────────────────────────────────────────

    #[signal]
    fn invoice_ready(player_index: i64, qr_bytes: PackedByteArray);

    /// Fired when a fixed-amount attack invoice settles.
    /// amount_sats equals the invoice amount, which is also the garbage line count.
    #[signal]
    fn invoice_paid(player_index: i64, amount_sats: i64);

    #[signal]
    fn address_checked(player_index: i64, is_valid: bool, message: GString);

    #[signal]
    fn payment_settled(amount_sats: i64, success: bool);
}
