defmodule BlindMixWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use BlindMixWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Mise en page commune : thème « Pop », barre de navigation (compte, profil) et messages flash.

      <Layouts.app flash={@flash} current_scope={@current_scope}>
        <h1>Contenu</h1>
      </Layouts.app>
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <BlindMixWeb.Pop.styles />

    <header class="bm-nav">
      <.link navigate={~p"/"} class="bm-brand" id="nav-home">
        <span class="bm-logo" aria-hidden="true">♫</span> Blind Mix
      </.link>

      <nav class="bm-nav-links" id="nav-account">
        <%= if @current_scope && @current_scope.user do %>
          <.link navigate={~p"/profile"} class="bm-pill" id="nav-profile">
            <.icon name="hero-user-circle-mini" class="size-5" /> Mon profil
          </.link>
          <.link
            navigate={~p"/users/settings"}
            class="bm-navlink bm-navlink--email"
            id="nav-settings"
            title="Réglages du compte"
          >
            {@current_scope.user.email}
          </.link>
          <.link href={~p"/users/log-out"} method="delete" class="bm-navlink" id="nav-log-out">
            Déconnexion
          </.link>
        <% else %>
          <.link navigate={~p"/users/log-in"} class="bm-navlink" id="nav-log-in">Connexion</.link>
          <.link navigate={~p"/users/register"} class="bm-pill" id="nav-register">
            Créer mon profil
          </.link>
        <% end %>
      </nav>
    </header>

    <main class="bm-wrap">
      {render_slot(@inner_block)}
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
