defmodule BlindMix.Repo.Migrations.CreateRoundsAndPlays do
  use Ecto.Migration

  def change do
    # Une manche terminée par un joueur connecté.
    create table(:rounds) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :score, :integer, null: false
      add :found_count, :integer, null: false
      add :track_count, :integer, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:rounds, [:user_id, :inserted_at])

    # Une piste jouée pendant une manche, et ce que le joueur en a fait.
    create table(:plays) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :round_id, references(:rounds, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :track_id, :string, null: false
      add :title, :string, null: false
      add :artist, :string, null: false
      # Nom d'artiste normalisé : regroupe « AC/DC » et « ac dc », même entre services.
      add :artist_key, :string, null: false
      add :result, :string, null: false
      add :points, :integer, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:plays, [:round_id])
    create index(:plays, [:user_id, :artist_key])
    create index(:plays, [:user_id, :provider, :track_id, :inserted_at])
  end
end
