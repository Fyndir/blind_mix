defmodule BlindMixWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use BlindMixWeb, :html

  embed_templates "page_html/*"

  @doc "Nom des services proposés, pour « Pas de compte … ? »."
  def services_label(true, true), do: "Deezer ou Spotify"
  def services_label(true, false), do: "Spotify"
  def services_label(false, true), do: "Deezer"
  def services_label(_, _), do: ""
end
