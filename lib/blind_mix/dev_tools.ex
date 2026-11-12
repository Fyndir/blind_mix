defmodule BlindMix.DevTools do
  @moduledoc """
  Outils de développement du jeu (simuler une piste trouvée, terminer une manche).

  Actifs en développement (`dev_routes` de dev.exs) ou avec `DEV_TOOLS=true`
  (ex. Docker en local). Ils sont revérifiés côté serveur : un événement forgé
  depuis le navigateur ne passe pas en production.
  """

  def enabled? do
    Application.get_env(:blind_mix, :dev_routes, false) == true or
      System.get_env("DEV_TOOLS") == "true"
  end
end
