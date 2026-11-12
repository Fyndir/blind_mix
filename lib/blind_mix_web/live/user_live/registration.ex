defmodule BlindMixWeb.UserLive.Registration do
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
              <span class="bm-play-text">Juste un e-mail, pas de mot de passe</span>
            </li>
          </ul>
        </div>

        <div class="bm-card">
          <.form for={@form} id="registration_form" phx-submit="save" phx-change="validate">
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
    changeset = Accounts.change_user_email(%User{}, %{}, validate_unique: false)

    {:ok, assign_form(socket, changeset), temporary_assigns: [form: nil]}
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
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

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_email(%User{}, user_params, validate_unique: false)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")
    assign(socket, form: form)
  end
end
