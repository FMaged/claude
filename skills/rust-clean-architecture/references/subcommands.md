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

