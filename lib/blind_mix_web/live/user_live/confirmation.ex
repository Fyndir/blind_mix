defmodule BlindMixWeb.UserLive.Confirmation do
  use BlindMixWeb, :live_view

  alias BlindMix.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="bm-auth">
        <div class="bm-center">
          <h1 class="bm-title">Bienvenue !</h1>
          <p class="bm-profile-name" style="margin-top:.5rem">{@user.email}</p>
        </div>

        <div class="bm-card">
          <.form
            :if={!@user.confirmed_at}
            for={@form}
            id="confirmation_form"
            phx-mounted={JS.focus_first()}
            phx-submit="submit"
            action={~p"/users/log-in?_action=confirmed"}
            phx-trigger-action={@trigger_submit}
            class="bm-stack"
            style="gap:.8rem"
          >
            <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
            <button
              name={@form[:remember_me].name}
              value="true"
              phx-disable-with="Confirmation…"
              class="bm-btn bm-btn--block"
            >
              Confirmer et rester connecté
            </button>
            <button phx-disable-with="Confirmation…" class="bm-btn bm-btn--ghost bm-btn--block">
              Confirmer juste pour cette fois
            </button>
          </.form>

          <.form
            :if={@user.confirmed_at}
            for={@form}
            id="login_form"
            phx-submit="submit"
            phx-mounted={JS.focus_first()}
            action={~p"/users/log-in"}
            phx-trigger-action={@trigger_submit}
            class="bm-stack"
            style="gap:.8rem"
          >
            <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
            <%= if @current_scope do %>
              <button phx-disable-with="Connexion…" class="bm-btn bm-btn--block">
                Se connecter
              </button>
            <% else %>
              <button
                name={@form[:remember_me].name}
                value="true"
                phx-disable-with="Connexion…"
                class="bm-btn bm-btn--block"
              >
                Rester connecté sur cet appareil
              </button>
              <button phx-disable-with="Connexion…" class="bm-btn bm-btn--ghost bm-btn--block">
                Me connecter juste cette fois
              </button>
            <% end %>
          </.form>
        </div>

        <p :if={!@user.confirmed_at} class="bm-muted bm-center">
          Astuce : tu pourras aussi définir un mot de passe dans les réglages du compte.
        </p>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    if user = Accounts.get_user_by_magic_link_token(token) do
      form = to_form(%{"token" => token}, as: "user")

      {:ok, assign(socket, user: user, form: form, trigger_submit: false),
       temporary_assigns: [form: nil]}
    else
      {:ok,
       socket
       |> put_flash(:error, "Ce lien n'est pas valide ou a expiré.")
       |> push_navigate(to: ~p"/users/log-in")}
    end
  end

  @impl true
  def handle_event("submit", %{"user" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: "user"), trigger_submit: true)}
  end
end
