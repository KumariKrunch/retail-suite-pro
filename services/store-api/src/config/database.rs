use serde::Deserialize;

#[derive(Deserialize)]
pub struct DatabaseConfig {
    pub user: String,
    pub password: String,
    pub database: String,
    pub host: String,
    pub port: u16,
}

impl std::fmt::Debug for DatabaseConfig {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("DatabaseConfig")
            .field("user", &self.user)
            .field("database", &self.database)
            .field("host", &self.host)
            .field("port", &self.port)
            .finish_non_exhaustive()
    }
}
