use super::log_install;
use std::fs;
use std::path::Path;

/// Replace or append a tagged activation line in a profile file.
pub fn update_tagged_profile_line(
    profile_path: &Path,
    profile_line: &str,
    activate_tag: &str,
    create_if_missing: bool,
    logging_enabled: bool,
) -> Result<(), String> {
    if !profile_path.exists() {
        if !create_if_missing {
            return Ok(());
        }
        fs::write(profile_path, "")
            .map_err(|err| format!("Could not create profile {}: {err}", profile_path.display()))?;
        log_install(logging_enabled, &format!("Created profile {}", profile_path.display()));
    }

    let existing = fs::read_to_string(profile_path)
        .map_err(|err| format!("Could not read profile {}: {err}", profile_path.display()))?;
    let mut lines = Vec::new();
    for existing_line in existing.lines() {
        if existing_line.contains(activate_tag) {
            continue;
        }
        lines.push(existing_line.to_string());
    }
    lines.push(format!("{profile_line} {activate_tag}"));
    let new_contents = format!("{}\n", lines.join("\n"));

    if existing == new_contents {
        log_install(logging_enabled, &format!("No changes to {}", profile_path.display()));
        return Ok(());
    }

    fs::write(profile_path, new_contents)
        .map_err(|err| format!("Could not update profile {}: {err}", profile_path.display()))?;
    log_install(
        logging_enabled,
        &format!("Updated activation in {}", profile_path.display()),
    );
    Ok(())
}
