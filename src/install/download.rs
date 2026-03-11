#[cfg(windows)]
use serde::de::DeserializeOwned;

/// Build the shared HTTP client used by installer downloads.
fn build_client() -> Result<reqwest::blocking::Client, String> {
    reqwest::blocking::Client::builder()
        .build()
        .map_err(|err| format!("Could not build HTTP client: {err}"))
}

/// Start a GET request and require a successful HTTP response.
fn get_response(url: &str) -> Result<reqwest::blocking::Response, String> {
    let response = build_client()?
        .get(url)
        .header(reqwest::header::USER_AGENT, "lfp-env-installer")
        .send()
        .map_err(|err| format!("Could not download {url}: {err}"))?;
    response
        .error_for_status()
        .map_err(|err| format!("Download failed for {url}: {err}"))
}

/// Download a text payload using the Rust HTTP client.
pub fn download_text(url: &str) -> Result<String, String> {
    get_response(url)?
        .text()
        .map_err(|err| format!("Could not read response body from {url}: {err}"))
}

#[cfg(windows)]
/// Download raw bytes for archive-based installer flows.
pub fn download_bytes(url: &str) -> Result<Vec<u8>, String> {
    get_response(url)?
        .bytes()
        .map(|bytes| bytes.to_vec())
        .map_err(|err| format!("Could not read downloaded bytes from {url}: {err}"))
}

#[cfg(windows)]
/// Download and parse a JSON response body.
pub fn download_json<T>(url: &str) -> Result<T, String>
where
    T: DeserializeOwned,
{
    get_response(url)?
        .json::<T>()
        .map_err(|err| format!("Could not parse JSON response from {url}: {err}"))
}
