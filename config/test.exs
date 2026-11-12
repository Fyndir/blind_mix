import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :blind_mix, BlindMixWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "ZwcNqGqjhK7nsT52z0KMeh0CxotS0CShVGTcxHHGxE7lu/t1u5m+ffIBr9h1wCaK",
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
