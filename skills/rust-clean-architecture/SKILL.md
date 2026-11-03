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

Read `references/config.md` before adding or changing config, env vars, or config files.

## 4. Postgres

Read `references/postgres.md` before touching the database, migrations, entities, or repositories.

## 5. Subcommands

Read `references/subcommands.md` before adding or changing a CLI subcommand.

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

Read `references/shutdown.md` before changing signal handling or task shutdown.

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
