defmodule BlindMix.DataCase do
  @moduledoc """
  Cas de test pour le code qui touche à la base.

  Chaque test tourne dans une transaction annulée à la fin (bac à sable SQL).
  Avec PostgreSQL, `use BlindMix.DataCase, async: true` est possible.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias BlindMix.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import BlindMix.DataCase
    end
  end

  setup tags do
    BlindMix.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc "Démarre le propriétaire du bac à sable pour ce test."
  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(BlindMix.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end

  @doc """
  Transforme les erreurs d'un changeset en map de messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
