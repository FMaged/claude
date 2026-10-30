---
name: rust-clean-architecture
description: Use when writing or changing a Rust application laid out as a Cargo workspace in clean (hexagonal) architecture — a domain crate with entities, use cases, and port traits, adapter crates (Postgres and others) that implement those traits, and a thin binary that loads config, parses subcommands, and wires them together — or when starting a new one (e.g. "add a use case", "add a repository", "where does this code go", "add a config value", "load config from a file and env", "connect to Postgres", "add a migration", "add a subcommand", "make it shut down cleanly", "start a new Rust service"). Covers tokio, clap, figment, dotenvy, sea-orm and sqlx, tracing, thiserror and anyhow. For a container image use container-builds; for CI, ci-pipelines.
---

# Rust clean architecture

Every piece of code is one of three things: **domain** (the rules, and the traits the rules
need from outside), **an adapter** (one crate that implements one of those traits against
one outside thing: Postgres, an HTTP API, a queue), or **wiring** (the binary that reads
config, parses the command, builds the adapters, and runs the use cases). Most mistakes in
these projects are code in the wrong one of the three.

The names below (`UserRepository`, `Notifier`, `WebhookConfig`) are placeholders. Use the
project's own.

For SQL use `sql-writing`; for a new table, `schema-design`; for a migration, `sql-review`;
for comments, `code-comments`. If the project has its own `CLAUDE.md` or invariants, they
win over anything here.

## 0. Read the project first

- Read the root `Cargo.toml`: `[workspace] members`, `[workspace.dependencies]`, edition,
  `rust-version`. Check the versions of sea-orm, sqlx, tokio, clap, and figment in
  `Cargo.lock` before writing against their APIs; sea-orm 0.12 and 1.x differ, and so do
  sqlx 0.7 and 0.8.
- Read the binary's `main.rs` top to bottom. It is the map: every adapter and the order of
  the run are there.
- `cargo tree -p domain` must show no I/O crate (sqlx, sea-orm, an HTTP client, clap,
  figment). If it does, the layering is already broken; say so before adding to it.
- Loose `.rs` files with no `Cargo.toml` are an excerpt. Say so, and work out which crate
  each file belongs to from its `use crate::…` paths instead of guessing.

## 1. Where code goes

```
Cargo.toml          [workspace], shared [workspace.dependencies]
Settings.toml       non-secret defaults, committed
.env.example        every APP_ variable name, no values
crates/
  domain/           entities, use_cases, ports (traits); no I/O crates
  storage/          Postgres: config, connection, repositories, sea-orm entities, migrations/
  <adapter>/        one crate per other outside thing; implements one domain trait
  app/              the binary: main.rs, config.rs, commands.rs, shutdown.rs
```

| You are adding | It goes in |
|---|---|
| A rule, or a type the rules talk about | `domain::entities` |
| A step the app performs | `domain::use_cases`, a struct with `new` and `exec` |
| Something a use case needs from outside (store, send, fetch) | a trait in `domain` |
| The Postgres or HTTP code behind that trait | its adapter crate |
| That adapter's settings | a `config` module in the adapter crate |
| A subcommand, config loading, logging, signals, building adapters | the binary |

An adapter depends on `domain` and its own driver, never on another adapter. The domain
depends on no adapter.

## 2. Domain and ports

- Only `serde`, `thiserror`, `tracing` (the macros), and pure-logic crates. No database,
  network, CLI, or config crate.
- Ports are traits the domain owns, named for what the domain needs (`UserRepository`,
  `Notifier`), not for the technology. Their methods take and return domain types and a
  domain error, never `sqlx::Error` or `sea_orm::DbErr`.
- `async fn` in a trait works since Rust 1.75, but the trait is not usable as `dyn` and the
  future has no `Send` bound, so `tokio::spawn` on it fails in generic code. Use generics
  (`RegisterUser<R: UserRepository>`), and add `#[trait_variant::make(Send)]` or
  `async-trait` only when you need `Send` or `dyn`.
- A use case is a struct that holds its ports (`Arc<R>` for one shared with other use
  cases), a `new(...)`, and one `async fn exec(&self) -> Result<_, Error>`. It does one
  thing. The binary chains them.
- Make wrong values impossible to build: newtypes with `try_new`, and a `HashSet` where
  order does not matter and duplicates are wrong. If two values mean the same thing (an
  unordered pair `(a, b)` and `(b, a)`), normalize in the constructor, or the set holds both.

## 3. Configuration

Each adapter owns its config type and takes it by reference in its constructor. It never
reads environment variables itself. The binary has one `ApplicationConfig` made of those
types, loaded once at startup (`app/src/config.rs`):

```rust
const DEFAULT_SETTINGS_FILE: &str = "Settings.toml";

#[derive(Debug, serde::Deserialize)]
pub(crate) struct ApplicationConfig {
    pub postgres_config: PostgresConfig,
    pub webhook_config: WebhookConfig,
}

impl ApplicationConfig {
    pub fn try_load() -> Result<Self, ApplicationConfigError> {
        let settings_file_path = Path::new(DEFAULT_SETTINGS_FILE);
        if settings_file_path.exists() && !settings_file_path.is_file() {
            return Err(ApplicationConfigError::SettingsFileNoFile(
                settings_file_path.to_owned(),
            ));
        }
        dotenvy::dotenv().ok();
        Figment::new()
            .merge(Toml::file(settings_file_path))
            .merge(Env::prefixed("APP_").split("__"))
            .extract()
            .map_err(|e| ApplicationConfigError::FigmentError(Box::new(e)))
    }
}
```

```toml
# Settings.toml — committed, no secrets
[postgres_config]
host = "localhost"
name = "app"
user = "app"
```

```sh
# .env.example — committed, names only; copy to .env for local runs
APP_POSTGRES_CONFIG__PASSWORD=
APP_WEBHOOK_CONFIG__TOKEN=
```

- Layers, last one wins: `Settings.toml` for non-secret defaults, then `APP_` environment
  variables, with `__` for nesting. The field `postgres_config.password` is
  `APP_POSTGRES_CONFIG__PASSWORD`. figment lowercases the keys.
- `.env` is only for local runs and is never committed. Load it with `dotenvy`. The `dotenv`
  crate is unmaintained (RUSTSEC-2021-0141).
- `Toml::file("Settings.toml")` is relative to the working directory, also searches the
  parent directories, and skips a missing file without an error. Under systemd, cron, or a
  container, set the working directory or take the path from a variable. Otherwise the only
  symptom is "missing field".
- `figment::Error` is large. Box it in the error variant, as above, so every `Result` that
  carries it stays small.
- A new value: add the field to the adapter's config type, a default in `Settings.toml` if
  it is not a secret, the variable name in `.env.example`, and a test for its newtype.

### Every value is a validated newtype

`#[serde(try_from = "String")]`, `TryFrom<String>`, `FromStr`, `Display`. Bad config fails
at startup, not at first use.

- Text that is not a secret (host, database name) is trimmed and must not be empty. Do not
  trim a password; spaces can be part of it.
- A number with a default keeps it in a `const` (`DEFAULT_PORT = 5432`,
  `DEFAULT_MAX_CONNECTIONS = 100`). Check ranges too: a pool size or a port of 0 passes a
  `u8` or `u16`.
- A `Default` impl is only used with `#[serde(default)]` on the field. Without it the value
  is required and the `Default` is dead code. Choose one.
- **Secrets** (passwords, tokens, API keys) get a hand-written `Debug` and `Display` that
  print `(sensitive value)`, and an accessor that is only `pub(crate)`. Anything that holds
  a secret redacts too: a connection URL, the whole config struct. A `#[derive(Debug)]` on a
  struct with a plain `String` password leaks it the first time someone logs the config.
  `secrecy::SecretString` does this for you.

```rust
#[derive(Clone, PartialEq, Eq, Hash, Deserialize)]
#[serde(try_from = "String")]
pub struct DatabasePassword(String);

impl DatabasePassword {
    pub(crate) fn as_str(&self) -> &str {
        &self.0
    }
}

impl TryFrom<String> for DatabasePassword {
    type Error = Error;

    fn try_from(value: String) -> Result<Self, Self::Error> {
        if value.is_empty() { Err(Error::PasswordEmpty) } else { Ok(Self(value)) }
    }
}

impl std::fmt::Debug for DatabasePassword {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_tuple("DatabasePassword")
            .field(&format_args!("(sensitive value)"))
            .finish()
    }
}

impl std::fmt::Display for DatabasePassword {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "(sensitive value)")
    }
}
```

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

## 5. Subcommands

clap derive, in `app/src/commands.rs`: the `Args` struct, one `Command` variant per
subcommand with its own args struct, and one function per subcommand.

```rust
#[derive(Debug, Parser)]
#[command(version, about)]
pub(crate) struct Args {
    #[command(subcommand)]
    pub command: Option<Command>,
}

#[derive(Debug, Subcommand)]
pub(crate) enum Command {
    /// Apply every pending database migration, or revert to an older one.
    Migrate(MigrateArgs),
}

#[derive(Debug, clap::Args)]
pub(crate) struct MigrateArgs {
    /// Revert down to this version instead of applying, e.g. 20240101120000.
    /// 0 reverts every migration.
    #[arg(long)]
    pub revert_to: Option<i64>,
}

pub(crate) async fn perform_migrations(args: MigrateArgs, postgres: &Postgres) -> anyhow::Result<()> {
    match args.revert_to {
        Some(version) => {
            info!(version, "Reverting migrations.");
            postgres.revert_migrations_to(version).await?;
        }
        None => {
            info!("Applying migrations.");
            postgres.apply_migrations().await?;
        }
    }
    Ok(())
}
```

- Doc comments on commands and arguments are the help text. Give an example value.
- A subcommand function takes its own args and only the adapters it needs, returns
  `anyhow::Result<()>`, and logs what it did. `main` only dispatches to it.
- A subcommand that needs no database (print the redacted config, check it) is dispatched
  before connecting (§6, step 5), so it works when Postgres is down.
- When a run with no subcommand writes data or calls out, prefer a named subcommand (`run`)
  for it, so a typo prints help instead of doing it.
- A destructive option (`--revert-to 0` reverts every migration) asks for confirmation or
  needs `--yes`.

## 6. The binary: order of `main`

1. Parse the CLI. `--help` and `--version` must work with no config and no database.
2. Start tracing, before anything that can log or fail.
3. Load and validate config.
4. Start the shutdown handler.
5. Connect to Postgres and the other outside services.
6. Dispatch on the subcommand. A maintenance command like `migrate` does its work and
   **returns**. It must not fall through into the main job.
7. Main job: check migrations, build adapters, run the use cases, report the result.
8. Cancel the token and wait for the closers (§7), on success and on error.

```rust
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let args = Args::parse();
    init_tracing();
    let application_config = ApplicationConfig::try_load()?;
    let cancellation_token = CancellationToken::new();
    let tracker = TaskTracker::new();
    tokio::spawn(shutdown_signals(cancellation_token.clone()));

    let postgres = connect_to_postgres(
        &application_config.postgres_config,
        cancellation_token.child_token(),
        &tracker,
    )
    .await?;

    let result = match args.command {
        Some(Command::Migrate(migrate_args)) => perform_migrations(migrate_args, &postgres).await,
        None => tokio::select! {
            r = run_job(&application_config, &postgres) => r,
            _ = cancellation_token.cancelled() => Err(anyhow!("stopped by shutdown signal")),
        },
    };

    cancellation_token.cancel();
    tracker.close();
    tracker.wait().await;
    result
}
```

```rust
async fn run_job(config: &ApplicationConfig, postgres: &Postgres) -> anyhow::Result<()> {
    let unapplied = postgres.unapplied_migrations().await?;
    if !unapplied.is_empty() {
        bail!("there are unapplied database migrations: {unapplied:?}; run `<bin> migrate`");
    }
    let users = Arc::new(PostgresUserRepository::new(postgres.db_connection()));
    let notifier = WebhookNotifier::new(&config.webhook_config)?;
    let count = NotifyInactiveUsers::new(users, notifier).exec().await?;
    info!(count, "Notified inactive users.");
    Ok(())
}
```

- Keep `main` a list of steps. Each step is a small `async fn` that logs what it did. Write
  helpers against the port traits (`fn report<R: UserRepository>(…)`), not the concrete
  adapters.
- A job that writes and then calls out must be safe to run twice: cron, systemd, and people
  all retry. Mark what was done (`sent_at`) and act only on what was not, or key each run by
  its period so a second run does nothing.
- In a long-running HTTP service, the main job is the server, and the same token drives
  `axum::serve(…).with_graceful_shutdown(token.cancelled_owned())`.

## 7. Graceful shutdown

One `CancellationToken` in `main`. One task waits for SIGINT or SIGTERM and cancels it
(`shutdown.rs`):

```rust
pub async fn shutdown_signals(cancellation_token: CancellationToken) {
    let ctrl_c = async {
        signal::ctrl_c()
            .await
            .expect("Ctrl+C handler should be installed");
    };
    let terminate = async {
        signal::unix::signal(signal::unix::SignalKind::terminate())
            .expect("terminate signal handler should be installed")
            .recv()
            .await;
    };

    tokio::select! {
        _ = ctrl_c => {},
        _ = terminate => {},
    }

    info!("Graceful shutdown requested.");
    cancellation_token.cancel();
}
```

Each resource gets a `child_token()` and closes itself, with a time limit, when it is
cancelled:

```rust
async fn connect_to_postgres(
    postgres_config: &PostgresConfig,
    cancellation_token: CancellationToken,
    tracker: &TaskTracker,
) -> anyhow::Result<Arc<Postgres>> {
    info!("Connecting to Postgres.");
    let postgres = Arc::new(Postgres::connect(postgres_config).await?);
    tracker.spawn({
        let postgres = postgres.clone();
        async move {
            cancellation_token.cancelled().await;
            info!("Closing Postgres connection.");
            if timeout(Duration::from_secs(10), postgres.close()).await.is_err() {
                warn!("Timed out while waiting for Postgres connection to close.");
            }
        }
    });
    Ok(postgres)
}
```

- A new outside resource with open connections follows the same shape: its own
  `connect_to_…`, its own child token, its own closer task.
- `signal::unix` exists only on Unix; put `terminate` behind `#[cfg(unix)]` if the project
  builds anywhere else.
- **The job must watch the token too.** Cancelling only closes the pool. A job that never
  looks at the token fails with a query error halfway through instead of stopping.
  `select!` on `cancellation_token.cancelled()` (§6), or check it between steps.
- **Cancel on the normal path too, and wait for the closers.** If nothing cancels the token
  when the job finishes, the closer never runs. When `main` returns, tokio drops tasks that
  have not finished. Spawn closers on a `TaskTracker` (`tokio_util::task`), and end `main`
  with `cancel()`, `tracker.close()`, `tracker.wait().await`.

## 8. Errors

- In `domain` and the adapters: `thiserror` enums, one per module, with messages a user
  understands. In the binary: `anyhow::Result`, `?`, and `.context("connecting to
  Postgres")` where the cause alone is unclear.
- Keep the cause once: either `#[source]` / `#[from]`, or `{0}` in the message, not both.
  `anyhow` prints the source chain, so with both the message repeats.
- `expect` only for what cannot fail in a correct program (installing a signal handler,
  setting the subscriber once). The message says what should have held.
- Say what to do next: "there are unapplied database migrations: [20240101120000]; run
  `<bin> migrate`" beats "pending migrations".

## 9. Logging

- `tracing` macros in every crate. Only the binary sets the subscriber.
- `EnvFilter::from_default_env()` shows only errors when `RUST_LOG` is not set. Fall back
  to a level:
  `EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info"))`.
- One line when each step starts and one with the result, with counts as fields:
  `info!(count = users.len(), "Loaded users.")`.
- Never log a secret or a whole config unless every secret in it is redacted (§3).
- Use JSON output (`fmt::layer().json()`) where the logs are collected by a machine.

## 10. Tests

- Use cases: unit tests with in-memory fakes of each port, no database. This is what the
  architecture is for.
- Repositories and migrations: integration tests against a real Postgres. `#[sqlx::test]`
  gives each test a new database with the migrations applied; wrap its pool for sea-orm with
  `SqlxPostgresConnector::from_sqlx_postgres_pool` and hand it to `Postgres::new`. `new` is
  `pub(crate)`, so these tests live in the storage crate's `src/`, not in `tests/`.
- Config: each newtype rejects bad input, and the `Debug` and `Display` of a secret, of
  `DatabaseUrl`, and of the whole `ApplicationConfig` never contain it.
- The binary: `--help` works with an empty environment.

## Before calling it done

```
cargo fmt --all --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
cargo tree -p domain      # no sqlx, sea-orm, HTTP client, clap, figment
cargo tree -d             # two versions of sqlx or tokio
cargo audit               # or: cargo deny check
<bin> --help              # with no config and no database
<bin> migrate && <bin> migrate --revert-to <previous> && <bin> migrate
```
