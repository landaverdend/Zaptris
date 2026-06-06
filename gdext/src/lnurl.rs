use std::time::Duration;

const CONNECT_TIMEOUT: Duration = Duration::from_secs(5);
const READ_TIMEOUT:    Duration = Duration::from_secs(10);

fn agent() -> ureq::Agent {
    ureq::AgentBuilder::new()
        .timeout_connect(CONNECT_TIMEOUT)
        .timeout(READ_TIMEOUT)
        .build()
}

fn lnurlp_url(address: &str) -> Result<String, String> {
    let address = address.trim();
    let (user, domain) = address
        .split_once('@')
        .filter(|(u, d)| !u.is_empty() && !d.is_empty())
        .ok_or_else(|| "Expected user@domain format".to_string())?;
    Ok(format!("https://{}/.well-known/lnurlp/{}", domain, user))
}

/// Validate a Lightning address by resolving its LNURL-pay endpoint.
/// Safe to call from any thread — uses ureq (sync HTTP, no async runtime).
pub fn check_address(address: &str) -> Result<(), String> {
    let url = lnurlp_url(address)?;
    let resp = agent().get(&url)
        .call()
        .map_err(|e| format!("Unreachable: {e}"))?;
    let json: serde_json::Value = resp
        .into_json()
        .map_err(|e| format!("Invalid JSON: {e}"))?;
    match json.get("tag").and_then(|t| t.as_str()) {
        Some("payRequest") => Ok(()),
        _ => Err("Not a valid LNURL-pay endpoint".to_string()),
    }
}

/// Fetch a BOLT-11 invoice for `amount_sats` from a Lightning address.
/// Two-step LNURL-pay: metadata fetch → callback → invoice.
/// Safe to call from any thread. Times out after 10s per request.
pub fn fetch_invoice(address: &str, amount_sats: u64) -> Result<String, String> {
    let url  = lnurlp_url(address)?;
    let http = agent();

    let meta: serde_json::Value = http.get(&url)
        .call()
        .map_err(|e| format!("Metadata fetch failed: {e}"))?
        .into_json()
        .map_err(|e| format!("Invalid JSON: {e}"))?;

    let callback = meta
        .get("callback")
        .and_then(|c| c.as_str())
        .ok_or_else(|| "No callback URL in LNURL-pay metadata".to_string())?;

    let amount_msats = amount_sats * 1_000;

    let min = meta.get("minSendable").and_then(|v| v.as_u64()).unwrap_or(0);
    let max = meta.get("maxSendable").and_then(|v| v.as_u64()).unwrap_or(u64::MAX);
    if amount_msats < min || amount_msats > max {
        return Err(format!(
            "Amount {}msats outside allowed range [{}, {}]",
            amount_msats, min, max
        ));
    }

    let sep = if callback.contains('?') { '&' } else { '?' };
    let callback_url = format!("{}{}amount={}", callback, sep, amount_msats);

    let inv: serde_json::Value = http.get(&callback_url)
        .call()
        .map_err(|e| format!("Invoice callback failed: {e}"))?
        .into_json()
        .map_err(|e| format!("Invalid invoice JSON: {e}"))?;

    inv.get("pr")
        .and_then(|pr| pr.as_str())
        .map(|s| s.to_string())
        .ok_or_else(|| "No 'pr' field in invoice response".to_string())
}
