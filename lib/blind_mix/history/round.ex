defmodule BlindMix.History.Round do
  @moduledoc "Une manche terminée, avec ses pistes (`plays`)."
  use Ecto.Schema

  alias BlindMix.Accounts.User
  alias BlindMix.History.Play

  schema "rounds" do
    field :provider, :string
    field :score, :integer
    field :found_count, :integer
    field :track_count, :integer

    belongs_to :user, User
    has_many :plays, Play, preload_order: [asc: :id]

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
