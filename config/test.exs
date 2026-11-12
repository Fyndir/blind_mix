import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# MIX_TEST_PARTITION permet de lancer les tests en parallèle sur plusieurs bases (CI).
config :blind_mix, BlindMix.Repo,
  username: "postgres",
  password: "postgres",
  hostname: System.get_env("DB_HOST", "localhost"),
  database: "blind_mix_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# Les e-mails sont capturés par les tests.
config :blind_mix, BlindMix.Mailer, adapter: Swoosh.Adapters.Test

# Pas de client HTTP Swoosh en test.
config :swoosh, :api_client, false

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :blind_mix, BlindMixWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "dVsAbF/SgsaYM6HxCztVSqP5d9eTx06on6jhqxrIS5QUoWX9oBLOkzuXBK1iX/WX",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Faux service musical, sans réseau, pour les tests du jeu.
config :blind_mix, :extra_providers, %{"fake" => BlindMix.FakeProvider}
