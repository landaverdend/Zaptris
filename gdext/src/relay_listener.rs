use std::sync::{mpsc, Mutex};
use std::thread;
use nostr_sdk::prelude::*;
use tokio::sync::oneshot;

/// Owned by RustBridge. Call stop() to shut down the listener.
pub struct ListenerHandle {
    stop_tx: Mutex<Option<oneshot::Sender<()>>>,
}

impl ListenerHandle {
    pub fn stop(&self) {
        if let Ok(mut guard) = self.stop_tx.lock() {
            if let Some(tx) = guard.take() {
                let _ = tx.send(());
            }
        }
    }
}

/// Spawn a background thread that subscribes to kind-9735 zap receipts
/// addressed to `zap_pubkey_hex` on relay.damus.io.
///
/// Parsed commands are pushed to `tx` as BridgeEvent::ZapCommand so
/// poll() can deliver them to GDScript on the main thread.
pub fn start_listening(
    zap_pubkey_hex: String,
    tx: mpsc::SyncSender<crate::BridgeEvent>,
) -> ListenerHandle {
    let (stop_tx, stop_rx) = oneshot::channel::<()>();

    thread::spawn(move || {
        let rt = tokio::runtime::Runtime::new()
            .expect("relay listener tokio runtime");
        rt.block_on(run_listener(zap_pubkey_hex, tx, stop_rx));
    });

    ListenerHandle {
        stop_tx: Mutex::new(Some(stop_tx)),
    }
}

async fn run_listener(
    zap_pubkey_hex: String,
    tx: mpsc::SyncSender<crate::BridgeEvent>,
    mut stop_rx: oneshot::Receiver<()>,
) {
    let pubkey = match PublicKey::from_hex(&zap_pubkey_hex) {
        Ok(pk) => pk,
        Err(e) => {
            eprintln!("[nostr] invalid zap pubkey '{zap_pubkey_hex}': {e}");
            return;
        }
    };

    eprintln!("[nostr] listening for zaps to pubkey {zap_pubkey_hex}");

    let keys  = Keys::generate();
    let client = Client::new(keys);

    // Subscribe to multiple relays — zap receipts are published to whatever
    // relays the sender's wallet specifies. Alby uses relay.getalby.com/v1.
    let relays = [
        "wss://relay.getalby.com/v1",
        "wss://relay.damus.io",
        "wss://relay.nostr.band",
        "wss://nos.lol",
    ];
    for url in relays {
        if let Err(e) = client.add_relay(url).await {
            eprintln!("[nostr] failed to add relay {url}: {e}");
        }
    }

    client.connect().await;
    tx.send(crate::BridgeEvent::Log(
        format!("[nostr] connected to {} relays, listening for zaps to {}", relays.len(), zap_pubkey_hex)
    )).ok();

    // kind 9735 = zap receipt, filtered to receipts addressed to the host wallet.
    // limit(0) = live events only, skip historical.
    let filter = Filter::new()
        .kind(Kind::Custom(9735))
        .pubkey(pubkey)
        .limit(0);

    match client.subscribe(vec![filter], None).await {
        Ok(output) => {
            tx.send(crate::BridgeEvent::Log(
                format!("[nostr] subscribed — id={:?}", output.val)
            )).ok();
        }
        Err(e) => {
            tx.send(crate::BridgeEvent::Log(
                format!("[nostr] subscribe FAILED: {e}")
            )).ok();
            return;
        }
    }

    let mut notifications = client.notifications();

    loop {
        tokio::select! {
            _ = &mut stop_rx => {
                eprintln!("[nostr] stop signal received");
                break;
            }
            result = notifications.recv() => {
                match result {
                    Ok(RelayPoolNotification::Event { event, .. }) => {
                        tx.send(crate::BridgeEvent::Log(
                            format!("[nostr] raw event received kind={} id={}", event.kind, event.id)
                        )).ok();
                        if let Some((player_idx, amount_sats, command)) = parse_zap_command(&event) {
                            tx.send(crate::BridgeEvent::Log(
                                format!("[nostr] zap parsed — player={player_idx} {amount_sats} sats cmd={command}")
                            )).ok();
                            tx.send(crate::BridgeEvent::ZapCommand(player_idx, amount_sats, command)).ok();
                        } else {
                            tx.send(crate::BridgeEvent::Log(
                                "[nostr] event received but no parseable command (check content format)".into()
                            )).ok();
                        }
                    }
                    Ok(_)  => {}
                    Err(e) => {
                        eprintln!("[nostr] notification error: {e}");
                        break;
                    }
                }
            }
        }
    }

    let _ = client.disconnect().await;
    eprintln!("[nostr] disconnected");
}

/// Extract a game command from a kind-9735 zap receipt.
///
/// Flow:
///   receipt["tags"]["description"] → zap request JSON
///   → zap request["content"]       → "0 GARBAGE"
///   → zap request["tags"]["amount"] → msats
///
/// Returns (player_index, amount_sats, COMMAND) or None if unparseable.
fn parse_zap_command(event: &Event) -> Option<(i64, i64, String)> {
    // Serialise the event to JSON and parse manually — avoids needing to
    // match on exact nostr-sdk Tag enum variants across versions.
    let event_val: serde_json::Value = serde_json::from_str(&event.as_json()).ok()?;
    let receipt_tags = event_val.get("tags")?.as_array()?;

    // Find ["description", "<zap_request_json>"]
    let desc_json = receipt_tags.iter()
        .find(|t| {
            t.as_array()
                .and_then(|a| a.first()?.as_str())
                == Some("description")
        })
        .and_then(|t| t.as_array()?.get(1)?.as_str())?;

    let zap_req: serde_json::Value = serde_json::from_str(desc_json).ok()?;

    // The bystander's free-text note — expected format: "0 GARBAGE"
    let content = zap_req.get("content")?.as_str()?.trim();
    if content.is_empty() {
        return None;
    }

    // Amount is in the zap request's "amount" tag, in millisats.
    let amount_msats: u64 = zap_req
        .get("tags")?
        .as_array()?
        .iter()
        .find(|t| {
            t.as_array()
                .and_then(|a| a.first()?.as_str())
                == Some("amount")
        })
        .and_then(|t| t.as_array()?.get(1)?.as_str()?.parse().ok())
        .unwrap_or(0);
    let amount_sats = (amount_msats / 1000) as i64;

    // Parse "PLAYER_IDX COMMAND" — e.g. "0 GARBAGE", "1 NUKE"
    let (idx_str, cmd) = content.split_once(' ')?;
    let player_idx: i64 = idx_str.trim().parse().ok()?;
    let command = cmd.trim().to_uppercase();

    Some((player_idx, amount_sats, command))
}
