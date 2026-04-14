pub type ConfigResult<T> = Result<T, ConfigError>;

#[derive(Debug)]
pub enum ConfigError {
    InvalidConfiguration(String),
    MissingConfiguration(String),
    Other(String),
}

impl std::fmt::Display for ConfigError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ConfigError::InvalidConfiguration(err) => write!(f, "Invalid configuration at {err}"),
            ConfigError::MissingConfiguration(path) => {
                write!(f, "Unable to find configuration file at {path}")
            }
            ConfigError::Other(err) => write!(f, "{err}"),
        }
    }
}

impl std::error::Error for ConfigError {}
