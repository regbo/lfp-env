use std::env;

/// Installer configuration read from environment variables.
pub struct InstallConfig {
    pub activate_profile: bool,
    pub disable_run: bool,
    pub logging_enabled: bool,
    pub forwarded_mise_args: Vec<String>,
}

impl InstallConfig {
    /// Build installer configuration from the current process environment.
    pub fn from_env(forwarded_mise_args: Vec<String>) -> Result<Self, String> {
        Ok(Self {
            activate_profile: read_bool_env("LFP_ENV_ACTIVATE_PROFILE", true)?,
            disable_run: read_bool_env("LFP_ENV_DISABLE_RUN", false)?,
            logging_enabled: read_bool_env("LFP_ENV_LOGGING_ENABLED", true)?,
            forwarded_mise_args,
        })
    }
}

fn read_bool_env(name: &str, default: bool) -> Result<bool, String> {
    let value = match env::var(name) {
        Ok(value) => value,
        Err(_) => {
            return Ok(default);
        }
    };

    match value.trim().to_ascii_lowercase().as_str() {
        "1" | "true" | "yes" | "on" => Ok(true),
        "0" | "false" | "no" | "off" => Ok(false),
        other => Err(format!(
            "Invalid value for {name}: '{other}'. Expected one of 1,0,true,false,yes,no,on,off"
        )),
    }
}
