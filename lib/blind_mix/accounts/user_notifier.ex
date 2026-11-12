defmodule BlindMix.Accounts.UserNotifier do
  @moduledoc "E-mails envoyés aux joueurs (connexion, confirmation, changement d'adresse)."
  import Swoosh.Email

  alias BlindMix.Mailer
  alias BlindMix.Accounts.User

  # Expéditeur configuré par MAIL_FROM (voir config/runtime.exs).
  defp sender,
    do: Application.get_env(:blind_mix, :mail_from, {"Blind Mix", "noreply@blindmix.local"})

  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from(sender())
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Envoie le lien de confirmation d'une nouvelle adresse e-mail.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Blind Mix : confirme ta nouvelle adresse", """
    Salut,

    Pour utiliser cette adresse sur ton profil Blind Mix, ouvre ce lien :

    #{url}

    Si tu n'as rien demandé, ignore simplement cet e-mail.

    — Blind Mix
    """)
  end

  @doc """
  Envoie un lien magique de connexion (ou de confirmation pour un nouveau compte).
  """
  def deliver_login_instructions(user, url) do
    case user do
      %User{confirmed_at: nil} -> deliver_confirmation_instructions(user, url)
      _ -> deliver_magic_link_instructions(user, url)
    end
  end

  defp deliver_magic_link_instructions(user, url) do
    deliver(user.email, "Blind Mix : ton lien de connexion", """
    Salut,

    Voici ton lien pour te connecter à Blind Mix :

    #{url}

    Il n'est valable que peu de temps. Si tu n'as rien demandé, ignore cet e-mail.

    — Blind Mix
    """)
  end

  defp deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Blind Mix : confirme ton profil", """
    Bienvenue sur Blind Mix !

    Pour confirmer ton profil et commencer à garder ton historique, ouvre ce lien :

    #{url}

    Si tu n'as pas créé de profil, ignore cet e-mail.

    — Blind Mix
    """)
  end
end
