use store_api_lib::{config::StoreApiConfig, constants::CONFIG_PATH};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    use std::env;

    let config_path = match env::var(CONFIG_PATH) {
        Ok(path) => path,
        Err(_e) => String::from(DEFAULT_CONFIG_PATH),
    };

    tracing::info!("Loading the config from {0}", config_path);

    let _config = match StoreApiConfig::load_config(&config_path) {
        Ok(config) => config,
        Err(e) => panic!("{}", e.to_string()),
    };

    Ok(())
}
