defmodule BlindMix.Startup do
  @moduledoc """
  Résumé de la configuration écrit dans les logs au démarrage : on voit d'un coup d'œil
  (dans les logs Render, par exemple) quelle base, quel service mail et quels services
  musicaux sont actifs, sans jamais afficher de secret.

      [démarrage] Blind Mix 0.1.0 prêt sur https://blind-mix.onrender.com
      [démarrage] base : externe (ep-xxx.eu-central-1.aws.neon.tech) · mail : désactivé ...
  """

  require Logger

  alias BlindMix.{Accounts, Admin, DevTools, Providers}

  def log do
    if Application.get_env(:blind_mix, :startup_log, true), do: do_log()
    :ok
  end

  defp do_log do
    vsn = Application.spec(:blind_mix, :vsn)
    Logger.info("[démarrage] Blind Mix #{vsn} prêt sur #{BlindMixWeb.Endpoint.url()}")

    Logger.info(
      "[démarrage] base : #{database()} · mail : #{mail()} · services : #{services()} · " <>
        "admins : #{admins()} · outils de dev : #{if DevTools.enabled?(), do: "oui", else: "non"}"
    )

    if Admin.admin_emails() == [] and not Application.get_env(:blind_mix, :dev_routes, false) do
      Logger.warning("[démarrage] aucun admin : renseigne ADMIN_EMAILS pour ouvrir /admin")
    end
  end

  defp database do
    config = BlindMix.Repo.config()

    host =
      case config[:url] do
        url when is_binary(url) -> URI.parse(url).host
        _ -> config[:hostname]
      end

    cond do
      host in ["127.0.0.1", "localhost", "::1", nil] -> "locale (#{host || "socket"})"
      true -> "externe (#{host})#{if config[:ssl], do: " en TLS", else: ""}"
    end
  end

  defp mail do
    if Accounts.mail_enabled?() do
      adapter = Application.get_env(:blind_mix, BlindMix.Mailer)[:adapter]
      "#{adapter |> Module.split() |> List.last()} (liens magiques)"
    else
      "désactivé (connexion par mot de passe)"
    end
  end

  defp services do
    Providers.names() |> Enum.filter(&Providers.available?/1) |> Enum.sort() |> Enum.join(", ")
  end

  defp admins do
    case Admin.admin_emails() do
      [] -> if Application.get_env(:blind_mix, :dev_routes), do: "tous (dev)", else: "aucun"
      emails -> "#{length(emails)}"
    end
  end
end
