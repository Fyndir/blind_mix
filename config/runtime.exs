import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/blind_mix start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :blind_mix, BlindMixWeb.Endpoint, server: true
end

config :blind_mix, BlindMixWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# Applications OAuth Deezer / Spotify (voir .env.example). Les variables absentes
# laissent seulement le mode démo utilisable.
config :blind_mix, :deezer,
  app_id: System.get_env("DEEZER_APP_ID"),
  secret: System.get_env("DEEZER_SECRET"),
  redirect_uri:
    System.get_env("DEEZER_REDIRECT_URI", "http://127.0.0.1:4000/auth/deezer/callback")

config :blind_mix, :spotify,
  client_id: System.get_env("SPOTIFY_CLIENT_ID"),
  client_secret: System.get_env("SPOTIFY_CLIENT_SECRET"),
  redirect_uri:
    System.get_env("SPOTIFY_REDIRECT_URI", "http://127.0.0.1:4000/auth/spotify/callback")

# Expéditeur des e-mails de connexion.
config :blind_mix,
       :mail_from,
       {"Blind Mix", System.get_env("MAIL_FROM", "noreply@blindmix.local")}

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :blind_mix, BlindMixWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        # Gettext translations
        ~r"priv/gettext/.*\.po$"E,
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/blind_mix_web/router\.ex$"E,
        ~r"lib/blind_mix_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  # Base hébergée (Neon, Supabase...) : leurs URL finissent par `?sslmode=require`.
  # On retire ces paramètres (inconnus d'Ecto) et on active TLS avec vérification du
  # certificat. DATABASE_SSL=true force TLS pour une URL sans paramètre.
  db_uri = URI.parse(database_url)
  db_query = URI.decode_query(db_uri.query || "")

  db_ssl? =
    System.get_env("DATABASE_SSL") in ~w(true 1) or
      db_query["sslmode"] in ~w(require verify-ca verify-full)

  db_ssl =
    if db_ssl? do
      [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        # Indispensable chez Neon, qui aiguille les connexions selon le nom d'hôte.
        server_name_indication: String.to_charlist(db_uri.host),
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ]
    else
      false
    end

  config :blind_mix, BlindMix.Repo,
    url: URI.to_string(%{db_uri | query: nil}),
    ssl: db_ssl,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  # E-mails de connexion (liens magiques). Sans MAIL_PROVIDER, aucun e-mail n'est envoyé :
  # inscription et connexion passent alors par un mot de passe.
  smtp_port = String.to_integer(System.get_env("SMTP_PORT", "587"))

  mailer =
    case System.get_env("MAIL_PROVIDER") do
      "resend" ->
        [adapter: Swoosh.Adapters.Resend, api_key: System.fetch_env!("MAIL_API_KEY")]

      "brevo" ->
        [adapter: Swoosh.Adapters.Brevo, api_key: System.fetch_env!("MAIL_API_KEY")]

      "postmark" ->
        [adapter: Swoosh.Adapters.Postmark, api_key: System.fetch_env!("MAIL_API_KEY")]

      # Serveur SMTP classique (Gmail avec mot de passe d'application, OVH, Infomaniak...).
      # Port 465 : SSL direct ; autres ports (587) : STARTTLS obligatoire.
      "smtp" ->
        [
          adapter: Swoosh.Adapters.SMTP,
          relay: System.fetch_env!("SMTP_HOST"),
          port: smtp_port,
          username: System.get_env("SMTP_USERNAME"),
          password: System.get_env("SMTP_PASSWORD"),
          auth: if(System.get_env("SMTP_USERNAME"), do: :always, else: :never),
          ssl: smtp_port == 465,
          tls: if(smtp_port == 465, do: :never, else: :always),
          tls_options: [verify: :verify_peer, cacerts: :public_key.cacerts_get(), depth: 3],
          retries: 2
        ]

      _ ->
        nil
    end

  if mailer do
    config :blind_mix, BlindMix.Mailer, mailer
    config :blind_mix, :mail_enabled, true
  else
    config :blind_mix, BlindMix.Mailer, adapter: Swoosh.Adapters.Logger, level: :info
    config :blind_mix, :mail_enabled, false
  end

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  # Phoenix exige au moins 64 octets. Une clé plus courte mais aléatoire (celle que
  # génère Render, par exemple) est étendue de façon déterministe par SHA-512.
  secret_key_base =
    if byte_size(secret_key_base) < 64,
      do: :crypto.hash(:sha512, secret_key_base) |> Base.encode64(),
      else: secret_key_base

  # Nom de domaine public : PHX_HOST, sinon celui que fournit Render
  # (RENDER_EXTERNAL_HOSTNAME), sinon localhost (conteneur autonome lancé en local).
  host =
    [System.get_env("PHX_HOST"), System.get_env("RENDER_EXTERNAL_HOSTNAME")]
    |> Enum.map(&String.trim(&1 || ""))
    |> Enum.find("localhost", &(&1 != ""))

  # URL de retour OAuth par défaut sur le domaine public (à déclarer chez Deezer/Spotify).
  if host != "localhost" do
    if System.get_env("DEEZER_REDIRECT_URI") in [nil, ""] do
      config :blind_mix, :deezer, redirect_uri: "https://#{host}/auth/deezer/callback"
    end

    if System.get_env("SPOTIFY_REDIRECT_URI") in [nil, ""] do
      config :blind_mix, :spotify, redirect_uri: "https://#{host}/auth/spotify/callback"
    end
  end

  config :blind_mix, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :blind_mix, BlindMixWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :blind_mix, BlindMixWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :blind_mix, BlindMixWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
