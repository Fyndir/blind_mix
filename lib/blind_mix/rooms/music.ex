defmodule BlindMix.Rooms.Music do
  @moduledoc """
  Accès à la musique pour les rooms : tubes de départ, élargissement autour des
  artistes trouvés, et extraits audio jouables.

  L'implémentation se choisit par `config :blind_mix, :room_music, Module`
  (`BlindMix.Rooms.DeezerMusic` par défaut, un faux service sans réseau en test).
  """

  @type track :: map()

  @doc "Tubes du moment, point de départ quand les joueurs n'ont pas de likes en commun."
  @callback hits() :: {:ok, [track()]} | {:error, term()}

  @doc "Autres titres des artistes donnés et d'artistes similaires."
  @callback expand(artist_ids :: [String.t()]) :: [track()]

  @doc "Titre avec une URL d'extrait audio fraîche, ou erreur s'il n'y en a pas."
  @callback resolve(track()) :: {:ok, track()} | {:error, term()}

  def impl, do: Application.get_env(:blind_mix, :room_music, BlindMix.Rooms.DeezerMusic)
end
