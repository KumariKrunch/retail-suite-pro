use config::{Config, ConfigError as ExternalConfigError};
use serde::Deserialize;

use crate::config::{
    database::DatabaseConfig,
    errors::{ConfigError, ConfigResult},
    telemetry::TelemetryConfig,
};

pub mod database;
pub mod errors;
pub mod telemetry;

#[derive(Debug, Deserialize)]
pub struct StoreApiConfig {
    pub database: DatabaseConfig,
    pub telemetry: TelemetryConfig,
}

impl StoreApiConfig {
    pub fn load_config(config_path: &str) -> ConfigResult<Self> {
        let config = Config::builder()
            .add_source(config::File::with_name(config_path))
            .add_source(config::Environment::with_prefix("APP"))
            .build()
            .map_err(|config_err| match config_err {
                ExternalConfigError::NotFound(path) => ConfigError::MissingConfiguration(path),
                _ => ConfigError::Other("Other Config Error".to_string()),
            })?;

        config
            .try_deserialize::<Self>()
            .map_err(|config_err| ConfigError::InvalidConfiguration(config_err.to_string()))
    }
}
