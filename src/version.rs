/// Compare program output version against a minimum version requirement.
/// Uses lenient semver parsing so common tool version formats still work.
pub fn is_version_at_least(output: &str, min_version: &str) -> bool {
    let current = extract_version_token(output).and_then(|token| lenient_semver::parse(&token).ok());
    let minimum = lenient_semver::parse(min_version).ok();
    match (current, minimum) {
        (Some(current_version), Some(minimum_version)) => current_version >= minimum_version,
        _ => false,
    }
}

/// Extract the first parseable version token from command output.
pub fn extract_version_token(output: &str) -> Option<String> {
    for raw_token in output.split_whitespace() {
        let cleaned = raw_token.trim_matches(|ch: char| !ch.is_ascii_alphanumeric() && ch != '.');
        if cleaned.is_empty() {
            continue;
        }
        if lenient_semver::parse(cleaned).is_ok() {
            return Some(cleaned.to_string());
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::{extract_version_token, is_version_at_least};

    #[test]
    fn parses_full_python_version() {
        let parsed = extract_version_token("Python 3.11.7");
        assert_eq!(parsed, Some("3.11.7".to_string()));
    }

    #[test]
    fn parses_prefixed_uv_version() {
        let parsed = extract_version_token("uv 0.5.22 (Homebrew 2025-03-01)");
        assert_eq!(parsed, Some("0.5.22".to_string()));
    }

    #[test]
    fn detects_minimum_version_success() {
        assert!(is_version_at_least("Python 3.10.1", "3.10"));
    }

    #[test]
    fn detects_minimum_version_failure() {
        assert!(!is_version_at_least("Python 3.9.21", "3.10"));
    }
}
