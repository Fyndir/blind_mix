defmodule BlindMixWeb.Router do
  use BlindMixWeb, :router

  import BlindMixWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BlindMixWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", BlindMixWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/auth/:provider", AuthController, :login
    get "/auth/:provider/callback", AuthController, :callback
    delete "/auth/logout", AuthController, :logout

    # Rooms multijoueur (avant la route LiveView /rooms/:code, pour /rooms/join).
    post "/rooms", RoomController, :create
    get "/rooms/join", RoomController, :find
    get "/rooms/:code/join", RoomController, :join_form
    post "/rooms/:code/join", RoomController, :join
  end

  # Other scopes may use custom stacks.
  # scope "/api", BlindMixWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:blind_mix, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: BlindMixWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", BlindMixWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{BlindMixWeb.UserAuth, :require_authenticated}] do
      # Profil et historique : réservés aux joueurs connectés.
      live "/profile", ProfileLive, :show
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", BlindMixWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{BlindMixWeb.UserAuth, :mount_current_scope}] do
      # Le jeu marche avec ou sans compte ; l'historique n'est gardé que pour les connectés.
      live "/play", GameLive, :play
      # Rooms multijoueur : ouvertes aux anonymes comme aux joueurs connectés.
      live "/rooms/:code", RoomLive, :show
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
