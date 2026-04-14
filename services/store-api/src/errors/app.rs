use std::env::VarError;

use crate::config::errors::ConfigError;

#[derive(Debug)]
pub enum AppError {
    EnvError(VarError),
    ConfigurationError(ConfigError),
}

impl std::fmt::Display for AppError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            AppError::ConfigurationError(config_error) => {
                write!(f, "Configuration Error: {config_error}")
            }
        }
    }
}

impl From<ConfigError> for AppError {
    fn from(value: ConfigError) -> Self {
        AppError::ConfigurationError(value)
    }
}
