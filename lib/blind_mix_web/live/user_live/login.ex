defmodule BlindMixWeb.UserLive.Login do
  use BlindMixWeb, :live_view

  alias BlindMix.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="bm-auth">
        <div class="bm-center">
          <h1 class="bm-title">Connexion</h1>
          <p class="bm-muted" style="margin-top:.5rem">
            <%= if @current_scope do %>
              Confirme ton identité pour modifier les réglages sensibles de ton compte.
            <% else %>
              Pas encore de profil ?
              <.link navigate={~p"/users/register"} class="bm-link">Crée-le en 10 secondes</.link>
            <% end %>
          </p>
        </div>

        <p :if={local_mail_adapter?()} class="bm-note" id="local-mailbox-note">
          <.icon name="hero-envelope-mini" class="size-5 shrink-0" />
          <span>
            Mode développement : les e-mails s'affichent dans <.link
              href="/dev/mailbox"
              class="bm-link"
            >la boîte de test</.link>.
          </span>
        </p>

        <div class="bm-card">
          <.form
            :let={f}
            for={@form}
            id="login_form_magic"
            action={~p"/users/log-in"}
            phx-submit="submit_magic"
          >
            <.input
              readonly={!!@current_scope}
              field={f[:email]}
              type="email"
              label="Ton e-mail"
              placeholder="toi@exemple.fr"
              autocomplete="username"
              spellcheck="false"
              required
              phx-mounted={JS.focus()}
            />
            <button class="bm-btn bm-btn--block" phx-disable-with="Envoi…">
              Recevoir mon lien de connexion
            </button>
          </.form>
          <p class="bm-muted bm-center" style="font-size:.85rem">
            Pas de mot de passe à retenir : on t'envoie un lien magique par e-mail.
          </p>
        </div>

        <details class="bm-details">
          <summary>Se connecter avec un mot de passe</summary>
          <div class="bm-card">
            <.form
              :let={f}
              for={@form}
              id="login_form_password"
              action={~p"/users/log-in"}
              phx-submit="submit_password"
              phx-trigger-action={@trigger_submit}
            >
              <.input
                readonly={!!@current_scope}
                field={f[:email]}
                type="email"
                label="E-mail"
                autocomplete="username"
                spellcheck="false"
                required
              />
              <.input
                field={@form[:password]}
                type="password"
                label="Mot de passe"
                autocomplete="current-password"
                spellcheck="false"
              />
              <div class="bm-stack" style="gap:.8rem">
                <button
                  class="bm-btn bm-btn--block"
                  name={@form[:remember_me].name}
                  value="true"
                >
                  Se connecter et rester connecté
                </button>
                <button class="bm-btn bm-btn--ghost bm-btn--block">
                  Se connecter juste cette fois
                </button>
              </div>
            </.form>
          </div>
        </details>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "user")

    {:ok, assign(socket, form: form, trigger_submit: false)}
  end

  @impl true
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end

  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_login_instructions(
        user,
        &url(~p"/users/log-in/#{&1}")
      )
    end

    info =
      "Si cette adresse a un profil, ton lien de connexion arrive dans quelques instants."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> push_navigate(to: ~p"/users/log-in")}
  end

  defp local_mail_adapter? do
    Application.get_env(:blind_mix, BlindMix.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
