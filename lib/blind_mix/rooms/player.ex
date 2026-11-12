defmodule BlindMix.Rooms.Player do
  @moduledoc """
  Un joueur dans une room.

  * `id` : `"u-<id>"` pour un joueur connecté à son profil (il garde sa place s'il
    recharge la page ou change d'appareil), aléatoire pour un anonyme ;
  * `user` : profil Blind Mix (`nil` pour un anonyme) ; ses manches sont enregistrées ;
  * `likes` : titres likés sur son service musical (`nil` s'il n'en a pas connecté) ;
  * `taste` : profil de goûts, chargé de la base pour un joueur connecté, construit
    au fil des manches pour un anonyme ;
  * `pids` : vues LiveView ouvertes (plusieurs onglets possibles).
  """

  alias BlindMix.Taste

  defstruct [
    :id,
    :name,
    :user,
    :likes,
    :likes_source,
    likes_status: :none,
    taste: %Taste{},
    score: 0,
    round_points: 0,
    ready?: false,
    pids: %{},
    joined_at: 0
  ]

  def connected?(%__MODULE__{pids: pids}), do: map_size(pids) > 0
end
