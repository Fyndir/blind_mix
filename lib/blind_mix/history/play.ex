defmodule BlindMix.History.Play do
  @moduledoc """
  Une piste jouée pendant une manche.

  `result` : `:title` (titre trouvé), `:artist` (artiste seulement) ou `:missed`.
  """
  use Ecto.Schema

  alias BlindMix.Accounts.User
  alias BlindMix.History.Round

  @results [:title, :artist, :missed]

  schema "plays" do
    field :provider, :string
    field :track_id, :string
    field :title, :string
    field :artist, :string
    field :artist_key, :string
    field :result, Ecto.Enum, values: @results
    field :points, :integer

    belongs_to :user, User
    belongs_to :round, Round

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def results, do: @results
end
