defmodule BlindMix.Matcher do
  @moduledoc """
  Compare une saisie à un titre ou un nom d'artiste, en tolérant :
  accents, majuscules, ponctuation, espaces ("ac dc" = "AC/DC"),
  "The" initial, "(feat. ...)", "- Remastered 2011" et petites fautes de frappe.
  """

  @threshold 0.92

  @doc "Vrai si `guess` correspond à `target`."
  def match?(guess, target) when is_binary(guess) and is_binary(target) do
    g = guess |> normalize(:loose) |> squash()

    g != "" and
      Enum.any?(candidates(target), fn candidate -> close?(g, squash(candidate)) end)
  end

  def match?(_, _), do: false

  @doc """
  Normalise un texte.

  * `:loose`  : accents, casse et ponctuation seulement (utilisé pour la saisie)
  * `:strict` : retire en plus `(...)`, `[...]` et le suffixe " - ..." (version courte du titre)
  """
  def normalize(text, mode \\ :loose) do
    text
    |> String.downcase()
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
    |> strip_extras(mode)
    |> String.replace("&", " and ")
    |> String.replace(~r/[^\p{L}\p{N}\s]/u, "")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
    |> String.replace_prefix("the ", "")
  end

  defp strip_extras(text, :loose), do: text

  defp strip_extras(text, :strict) do
    text
    |> String.replace(~r/[\(\[].*?[\)\]]/u, " ")
    |> String.replace(~r/\s-\s.*$/u, " ")
  end

  # La cible est acceptée sous sa forme complète ET sous sa forme courte.
  defp candidates(target) do
    Enum.uniq([normalize(target, :loose), normalize(target, :strict)])
  end

  defp squash(text), do: String.replace(text, " ", "")

  defp close?(_guess, ""), do: false
  defp close?(same, same), do: true

  # La tolérance aux fautes ne s'applique qu'aux cibles d'au moins 5 caractères.
  defp close?(guess, target) do
    String.length(target) >= 5 and String.jaro_distance(guess, target) >= @threshold
  end
end
