## 4. Postgres

### Config and the connection URL

`PostgresConfig` lives in the storage crate and is built only from newtypes, so deriving
`Debug` on it is safe:

```rust
#[derive(Debug, Clone, Deserialize)]
pub struct PostgresConfig {
    pub host: DatabaseHost,
    #[serde(default)]
    pub port: DatabasePort,
    pub name: DatabaseName,
    pub user: DatabaseUser,
    pub password: DatabasePassword,
    #[serde(default)]
    pub max_connections: MaxConnections,
}

impl PostgresConfig {
    pub fn database_url(&self) -> DatabaseUrl<'_> {
        DatabaseUrl(self)
    }
}
```

The URL is its own type that borrows the config. `Debug` and `Display` print
`postgresql://(sensitive value):(sensitive value)@host:port/db`; only `as_string()` gives the
real URL. Percent-encode the user and password there. A password with `@`, `:`, `/`, `#`,
or `%` breaks a plain `format!`; sqlx decodes them again.

```rust
pub struct DatabaseUrl<'a>(&'a PostgresConfig);

impl DatabaseUrl<'_> {
    pub(crate) fn as_string(&self) -> String {
        let c = self.0;
        format!(
            "postgresql://{}:{}@{}:{}/{}",
            utf8_percent_encode(c.user.as_str(), NON_ALPHANUMERIC),
            utf8_percent_encode(c.password.as_str(), NON_ALPHANUMERIC),
            c.host,
            c.port,
            c.name,
        )
    }
}
```

### One pool, shared

Postgres is one `Postgres` struct around one pool. The binary makes it once; every
repository gets `postgres.db_connection()` in its constructor:

```rust
#[derive(Debug, Clone)]
pub struct Postgres {
    db_connection: Arc<DatabaseConnection>,
}

impl Postgres {
    pub async fn connect(postgres_config: &PostgresConfig) -> Result<Self, DbError> {
        let mut options = ConnectOptions::new(postgres_config.database_url().as_string());
        options.max_connections(postgres_config.max_connections.into());
        let db = Database::connect(options).await?;
        Ok(Self::new(db))
    }

    pub async fn close(&self) -> Result<(), DbError> {
        self.db_connection().close_by_ref().await?;
        Ok(())
    }

    pub fn db_connection(&self) -> Arc<DatabaseConnection> {
        self.db_connection.clone()
    }

    /// This constructor mainly exists for testing.
    pub(crate) fn new(db_connection: DatabaseConnection) -> Self {
        Self { db_connection: Arc::new(db_connection) }
    }
}
```

- `ConnectOptions` logs every statement at `info` by default. Turn it down with
  `sqlx_logging_level(log::LevelFilter::Debug)` or off with `sqlx_logging(false)`.

### Repositories

- One repository struct per port, holding the `Arc<DatabaseConnection>`, implementing the
  domain trait.
- sea-orm entities (`Model`, `ActiveModel`) never leave the storage crate. Convert to and
  from the domain entity with `TryFrom` inside the adapter; a row that does not make a
  valid domain value is an error, not a panic.
- Turn the driver's error into the domain error at the edge, keeping the cause as the
  source (`impl From<sea_orm::DbErr> for DbError`). Give the caller variants it can act on
  (`NotFound`, `Connection`, `Query`), not one catch-all.
- Rows that must land together are written in one transaction
  (`db_connection.begin().await?` … `txn.commit().await?`).

### Migrations

Migrations are another `impl Postgres` block (`migration.rs`) that runs sqlx on the same
pool. Use the sqlx version sea-orm uses, or two sqlx versions end up in the build;
`cargo tree -i sqlx` shows it.

```rust
static MIGRATOR: Migrator = sqlx::migrate!();

impl Postgres {
    pub async fn apply_migrations(&self) -> Result<(), DbError> {
        MIGRATOR.run(self.db_connection.get_postgres_connection_pool()).await?;
        Ok(())
    }

    pub async fn revert_migrations_to(&self, version: i64) -> Result<(), DbError> {
        MIGRATOR.undo(self.db_connection.get_postgres_connection_pool(), version).await?;
        Ok(())
    }

    pub async fn unapplied_migrations(&self) -> Result<Vec<i64>, DbError> {
        let pool = self.db_connection.get_postgres_connection_pool();
        let applied: Vec<i64> =
            match sqlx::query_scalar("SELECT version FROM _sqlx_migrations WHERE success")
                .fetch_all(pool)
                .await
            {
                Ok(versions) => versions,
                // 42P01: the table does not exist yet, so nothing is applied.
                Err(sqlx::Error::Database(e)) if e.code().as_deref() == Some("42P01") => {
                    Vec::new()
                }
                Err(e) => return Err(e.into()),
            };
        Ok(MIGRATOR
            .iter()
            .filter(|m| !m.migration_type.is_down_migration())
            .map(|m| m.version)
            .filter(|v| !applied.contains(v))
            .collect())
    }
}
```

- `sqlx::migrate!()` embeds the `migrations/` folder of the crate that calls it, at compile
  time. Add one there with `sqlx migrate add -r <name>`, which writes an `.up.sql` and a
  `.down.sql`. Run `sqlx migrate build-script` once, so a new `.sql` file alone triggers a
  rebuild.
- Never edit an applied migration. sqlx stores a checksum and refuses to run
  (`VersionMismatch`). Add a new one.
- Apply migrations with the `migrate` subcommand (§5) as a separate deploy step. On a normal
  run the app calls `unapplied_migrations()` and refuses to start if it is not empty.
- Try every `down` before you call it done: `migrate`, `migrate --revert-to <previous>`,
  `migrate`.

