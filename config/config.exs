# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :blind_mix, :scopes,
  user: [
    default: true,
    module: BlindMix.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: BlindMix.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :blind_mix,
  ecto_repos: [BlindMix.Repo],
  generators: [timestamp_type: :utc_datetime]

# Envoi des e-mails (liens de connexion). En dev, ils sont visibles sur /dev/mailbox ;
# en prod, l'adaptateur est configuré dans runtime.exs.
config :blind_mix, BlindMix.Mailer, adapter: Swoosh.Adapters.Local

# Les liens magiques sont envoyés par e-mail (en prod, dépend de MAIL_PROVIDER : runtime.exs).
config :blind_mix, :mail_enabled, true

# Interface et messages de validation en français.
config :blind_mix, BlindMixWeb.Gettext, default_locale: "fr"

# Configure the endpoint
config :blind_mix, BlindMixWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: BlindMixWeb.ErrorHTML, json: BlindMixWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: BlindMix.PubSub,
  live_view: [signing_salt: "qcK7sXMd"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  blind_mix: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.3",
  blind_mix: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
