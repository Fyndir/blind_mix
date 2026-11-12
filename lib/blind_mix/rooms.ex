defmodule BlindMix.Rooms do
  @moduledoc """
  Rooms multijoueur : création, arrivée des joueurs, manches en mode course.

  Chaque room est un processus (`BlindMix.Rooms.Server`) identifié par un code court
  (ex. `K7RX2`), à partager avec les autres joueurs. Une room sans joueur connecté
  s'arrête d'elle-même au bout de quelques minutes.

  Les vues s'abonnent avec `subscribe/1` et reçoivent `{:room, état_public}` à
  chaque changement.
  """

  alias BlindMix.Rooms.Server

  # Sans caractères ambigus (0/O, 1/I/L) : le code se dicte facilement.
  @alphabet ~c"ABCDEFGHJKMNPQRSTUVWXYZ23456789"
  @code_length 5

  @doc "Crée une room et renvoie son code."
  def create_room do
    code = random_code()

    case DynamicSupervisor.start_child(BlindMix.Rooms.Supervisor, {Server, code}) do
      {:ok, _pid} -> {:ok, code}
      {:error, {:already_started, _pid}} -> create_room()
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Code saisi par un joueur, remis en forme (`\" k7rx2 \"` → `\"K7RX2\"`), ou `nil`."
  def normalize_code(code) when is_binary(code) do
    code = code |> String.trim() |> String.upcase()
    if code =~ ~r/^[A-Z0-9]{#{@code_length}}$/, do: code
  end

  def normalize_code(_code), do: nil

  @doc "Vrai si la room existe (et tourne encore)."
  def exists?(code) when is_binary(code),
    do: Registry.lookup(BlindMix.Rooms.Registry, code) != []

  def exists?(_code), do: false

  def subscribe(code), do: Phoenix.PubSub.subscribe(BlindMix.PubSub, "room:" <> code)

  @doc """
  Fait entrer (ou revenir) un joueur. `info` : `%{id, name, user}`. Le processus `pid`
  est surveillé : quand toutes ses vues sont fermées, le joueur apparaît déconnecté.
  """
  def join(code, info, pid \\ self()), do: call(code, {:join, info, pid})

  @doc "Likes du joueur : `:loading`, `:error`, `:none` ou `{:ready, titres, service}`."
  def set_likes(code, player_id, status), do: call(code, {:likes, player_id, status})

  def set_ready(code, player_id, ready?), do: call(code, {:ready, player_id, ready?})

  @doc "Lance une manche (réservé à l'hôte, entre deux manches)."
  def start_round(code, player_id), do: call(code, {:start_round, player_id})

  @doc "Proposition d'un joueur ; renvoie `{:ok, hits}` comme `BlindMix.Game.guess/2`."
  def guess(code, player_id, text), do: call(code, {:guess, player_id, text})

  @doc "Outil de développement : piste `track_id` trouvée (`:title` ou `:artist`) par ce joueur."
  def dev_found(code, player_id, track_id, kind),
    do: call(code, {:dev_found, player_id, track_id, kind})

  @doc "Outil de développement : termine la manche en cours."
  def dev_finish(code), do: call(code, :dev_finish)

  def state(code), do: call(code, :state)

  defp call(code, message) do
    GenServer.call(Server.via(code), message)
  catch
    :exit, {:noproc, _} -> {:error, :not_found}
    :exit, {{:shutdown, _}, _} -> {:error, :not_found}
    :exit, {:normal, _} -> {:error, :not_found}
  end

  defp random_code do
    for _ <- 1..@code_length, into: "", do: <<Enum.random(@alphabet)>>
  end
end
