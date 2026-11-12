defmodule BlindMixWeb.UserLive.Registration do
  @moduledoc """
  Création de profil.

  * Avec un service mail configuré : un e-mail suffit, on reçoit un lien de connexion.
  * Sans service mail (conteneur autonome) : e-mail + mot de passe, connexion immédiate.
  """
  use BlindMixWeb, :live_view

  alias BlindMix.Accounts
  alias BlindMix.Accounts.User

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="bm-auth">
        <div class="bm-center">
          <h1 class="bm-title">Crée ton profil</h1>
          <p class="bm-muted" style="margin-top:.5rem">
            Déjà inscrit·e ? <.link navigate={~p"/users/log-in"} class="bm-link">Connecte-toi</.link>
          </p>
        </div>

        <div class="bm-card" id="register-perks">
          <ul class="bm-plays" style="gap:.7rem">
            <li class="bm-play bm-play--title">
              <span class="bm-play-dot" aria-hidden="true">📜</span>
              <span class="bm-play-text">Tout ton historique de manches, titre par titre</span>
            </li>
            <li class="bm-play bm-play--artist">
              <span class="bm-play-dot" aria-hidden="true">🎯</span>
              <span class="bm-play-text">Des manches qui ciblent de plus en plus tes goûts</span>
            </li>
            <li class="bm-play bm-play--title">
              <span class="bm-play-dot" aria-hidden="true">🔑</span>
              <span class="bm-play-text">
                {if @mail?,
                  do: "Juste un e-mail, pas de mot de passe",
                  else: "Un e-mail et un mot de passe, c'est tout"}
              </span>
            </li>
          </ul>
        </div>

        <div class="bm-card">
          <.form
            :if={@mail?}
            for={@form}
            id="registration_form"
            phx-submit="save"
            phx-change="validate"
          >
            <.input
              field={@form[:email]}
              type="email"
              label="Ton e-mail"
              placeholder="toi@exemple.fr"
              autocomplete="username"
              spellcheck="false"
              required
              phx-mounted={JS.focus()}
            />

            <button phx-disable-with="Création…" class="bm-btn bm-btn--block">
              Créer mon profil
            </button>
          </.form>

          <.form
            :if={not @mail?}
            for={@form}
            id="registration_form"
            action={~p"/users/log-in?_action=registered"}
            phx-submit="save"
            phx-change="validate"
            phx-trigger-action={@trigger_submit}
          >
            <.input
              field={@form[:email]}
              type="email"
              label="Ton e-mail"
              placeholder="toi@exemple.fr"
              autocomplete="username"
              spellcheck="false"
              required
              phx-mounted={JS.focus()}
            />
            <.input
              field={@form[:password]}
              type="password"
              label="Mot de passe (12 caractères minimum)"
              autocomplete="new-password"
              spellcheck="false"
              required
            />
            <.input
              field={@form[:password_confirmation]}
              type="password"
              label="Confirme le mot de passe"
              autocomplete="new-password"
              spellcheck="false"
              required
            />
            <input type="hidden" name={@form[:remember_me].name} value="true" />

            <button phx-disable-with="Création…" class="bm-btn bm-btn--block">
              Créer mon profil
            </button>
          </.form>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: user}}} = socket)
      when not is_nil(user) do
    {:ok, redirect(socket, to: BlindMixWeb.UserAuth.signed_in_path(socket))}
  end

  def mount(_params, _session, socket) do
    mail? = Accounts.mail_enabled?()

    socket =
      socket
      |> assign(mail?: mail?, trigger_submit: false)
      |> assign_form(change(mail?, %{}))

    {:ok, socket, temporary_assigns: [form: nil]}
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, %{assigns: %{mail?: true}} = socket) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        {:ok, _} =
          Accounts.deliver_login_instructions(
            user,
            &url(~p"/users/log-in/#{&1}")
          )

        {:noreply,
         socket
         |> put_flash(
           :info,
           "Un e-mail vient de partir vers #{user.email} : ouvre-le pour confirmer ton profil."
         )
         |> push_navigate(to: ~p"/users/log-in")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  # Sans e-mail : le compte est créé, puis le formulaire est envoyé au contrôleur de
  # session (phx-trigger-action) qui connecte le joueur avec son mot de passe.
  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.register_user_with_password(user_params) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> assign(trigger_submit: true)
         |> assign(form: to_form(user_params, as: "user"))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = change(socket.assigns.mail?, user_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp change(true = _mail?, params),
    do: Accounts.change_user_email(%User{}, params, validate_unique: false)

  defp change(false = _mail?, params),
    do:
      Accounts.change_user_registration(%User{}, params,
        validate_unique: false,
        hash_password: false
      )

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, form: to_form(changeset, as: "user"))
  end
end
