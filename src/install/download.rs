/// Download a text payload using the Rust HTTP client.
pub fn download_text(url: &str) -> Result<String, String> {
    let client = reqwest::blocking::Client::builder()
        .build()
        .map_err(|err| format!("Could not build HTTP client: {err}"))?;
    let response = client
        .get(url)
        .send()
        .map_err(|err| format!("Could not download {url}: {err}"))?;
    let response = response
        .error_for_status()
        .map_err(|err| format!("Download failed for {url}: {err}"))?;
    response
        .text()
        .map_err(|err| format!("Could not read response body from {url}: {err}"))
}
