defmodule BlindMix.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BlindMixWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:blind_mix, :dns_cluster_query) || :ignore},
      BlindMix.Repo,
      {Phoenix.PubSub, name: BlindMix.PubSub},
      # Tâches de fond (préparation des manches, recherche de titres) et rooms multijoueur.
      {Task.Supervisor, name: BlindMix.TaskSupervisor},
      {Registry, keys: :unique, name: BlindMix.Rooms.Registry},
      {DynamicSupervisor, name: BlindMix.Rooms.Supervisor, strategy: :one_for_one},
      # Start to serve requests, typically the last entry
      BlindMixWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: BlindMix.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BlindMixWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
