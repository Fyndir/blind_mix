defmodule BlindMix.Release do
  @moduledoc """
  Tâches lancées depuis une release, sans Mix (voir `rel/overlays/bin/migrate`).
  """
  @app :blind_mix

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)

  defp load_app do
    # Les connexions à la base peuvent passer par SSL.
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
