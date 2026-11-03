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

