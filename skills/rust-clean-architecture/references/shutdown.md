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

