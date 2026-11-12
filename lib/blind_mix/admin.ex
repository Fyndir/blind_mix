defmodule BlindMix.Admin do
  @moduledoc """
  Administration du site : qui est admin, statistiques, gestion des comptes et des rooms.

  Les admins sont les comptes dont l'e-mail figure dans `ADMIN_EMAILS` (liste séparée
  par des virgules). En développement, sans `ADMIN_EMAILS`, tout compte connecté est admin.
  """

  import Ecto.Query
  require Logger

  alias BlindMix.Accounts.{User, UserToken}
  alias BlindMix.History.{Play, Round}
  alias BlindMix.{Repo, Rooms}

  @doc "Vrai si ce compte a accès à l'administration."
  def admin?(%User{email: email}) do
    case admin_emails() do
      [] -> open_in_dev?()
      emails -> String.downcase(email) in emails
    end
  end

  def admin?(_user), do: false

  @doc "E-mails admin configurés, en minuscules (lus dans `ADMIN_EMAILS` par config/runtime.exs)."
  def admin_emails, do: Application.get_env(:blind_mix, :admin_emails, [])

  defp open_in_dev?, do: Application.get_env(:blind_mix, :dev_routes, false) == true

  # --- Statistiques ----------------------------------------------------------------

  def stats do
    now = DateTime.utc_now(:second)
    day = DateTime.add(now, -1, :day)
    week = DateTime.add(now, -7, :day)

    %{
      users: Repo.aggregate(User, :count),
      users_week: Repo.aggregate(from(u in User, where: u.inserted_at >= ^week), :count),
      rounds: Repo.aggregate(Round, :count),
      rounds_day: Repo.aggregate(from(r in Round, where: r.inserted_at >= ^day), :count),
      plays: Repo.aggregate(Play, :count),
      rooms: length(Rooms.list_codes())
    }
  end

  # --- Comptes ---------------------------------------------------------------------

  @doc """
  Comptes les plus récents (50 par défaut), filtrés par un morceau d'e-mail, avec leur
  nombre de manches et la date de la dernière.
  """
  def list_users(search \\ "", limit \\ 50) do
    rounds =
      from r in Round,
        group_by: r.user_id,
        select: %{user_id: r.user_id, count: count(r.id), last_at: max(r.inserted_at)}

    query =
      from u in User,
        left_join: r in subquery(rounds),
        on: r.user_id == u.id,
        order_by: [desc: u.inserted_at, desc: u.id],
        limit: ^limit,
        select: %{
          id: u.id,
          email: u.email,
          inserted_at: u.inserted_at,
          confirmed_at: u.confirmed_at,
          rounds: coalesce(r.count, 0),
          last_round_at: r.last_at
        }

    query =
      case String.trim(search || "") do
        "" -> query
        text -> where(query, [u], ilike(u.email, ^"%#{escape_like(text)}%"))
      end

    Repo.all(query)
  end

  @doc """
  Supprime un compte avec son historique (suppression en cascade). Renvoie les jetons de
  session du compte, pour couper ses connexions en cours. Un admin ne peut pas se supprimer
  lui-même depuis l'administration.
  """
  def delete_user(%User{id: id}, id), do: {:error, :self}

  def delete_user(%User{} = admin, user_id) do
    with %User{} = user <- Repo.get(User, user_id),
         tokens = Repo.all(from t in UserToken, where: t.user_id == ^user.id),
         {:ok, _user} <- Repo.delete(user) do
      Logger.info("[admin] compte #{user.id} supprimé par l'admin #{admin.id}")
      {:ok, tokens}
    else
      nil -> {:error, :not_found}
      {:error, _changeset} = error -> error
    end
  end

  # --- Rooms -----------------------------------------------------------------------

  @doc "Rooms ouvertes, les plus actives d'abord."
  def list_rooms do
    Rooms.list_codes()
    |> Enum.flat_map(fn code ->
      case Rooms.state(code) do
        %{players: players} = room ->
          connected = Enum.filter(players, & &1.connected?)

          [
            %{
              code: code,
              status: room.status,
              round_id: room.round_id,
              players: Enum.map(connected, & &1.name),
              total_players: length(players)
            }
          ]

        _gone ->
          []
      end
    end)
    |> Enum.sort_by(&{-length(&1.players), &1.code})
  end

  def close_room(%User{} = admin, code) do
    case Rooms.close(code) do
      :ok ->
        Logger.info("[admin] room #{code} fermée par l'admin #{admin.id}")
        :ok

      error ->
        error
    end
  end

  defp escape_like(text), do: String.replace(text, ~r/[\\%_]/, "\\\\\\0")
end
