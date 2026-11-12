defmodule BlindMix.AdminTest do
  # Modifie la config :admin_emails et utilise des rooms : pas d'async.
  use BlindMix.DataCase, async: false

  import BlindMix.AccountsFixtures

  alias BlindMix.{Admin, History, Rooms}
  alias BlindMix.Accounts.{Scope, User, UserToken}

  setup do
    previous = Application.get_env(:blind_mix, :admin_emails)
    on_exit(fn -> Application.put_env(:blind_mix, :admin_emails, previous) end)
    :ok
  end

  describe "admin?/1" do
    test "vrai pour les e-mails de ADMIN_EMAILS, quelle que soit la casse" do
      Application.put_env(:blind_mix, :admin_emails, ["chef@example.com"])

      assert Admin.admin?(%User{email: "Chef@Example.com"})
      refute Admin.admin?(%User{email: "joueur@example.com"})
      refute Admin.admin?(nil)
    end

    test "sans ADMIN_EMAILS, personne n'est admin hors développement" do
      Application.put_env(:blind_mix, :admin_emails, [])
      refute Admin.admin?(%User{email: "chef@example.com"})
    end
  end

  describe "comptes" do
    test "list_users/1 compte les manches et filtre par e-mail" do
      alice = user_fixture(%{email: "alice@example.com"})
      _bob = user_fixture(%{email: "bob@example.com"})

      track = %{id: "t1", title: "Titre", artist: "Artiste", preview_url: nil}
      {:ok, _} = History.record_results(Scope.for_user(alice), "demo", [{track, :title}])

      assert [%{email: "alice@example.com", rounds: 1, last_round_at: %DateTime{}}] =
               Admin.list_users("ALICE")

      emails = Admin.list_users("") |> Enum.map(& &1.email)
      assert "alice@example.com" in emails and "bob@example.com" in emails

      # Les jokers SQL saisis sont pris littéralement.
      assert Admin.list_users("%") == []
    end

    test "delete_user/2 supprime le compte, son historique et rend ses jetons" do
      admin = user_fixture()
      user = user_fixture()
      track = %{id: "t1", title: "Titre", artist: "Artiste", preview_url: nil}
      {:ok, _} = History.record_results(Scope.for_user(user), "demo", [{track, :missed}])
      BlindMix.Accounts.generate_user_session_token(user)

      assert {:ok, [%UserToken{} | _]} = Admin.delete_user(admin, user.id)
      refute Repo.get(User, user.id)
      assert History.stats(Scope.for_user(user)).rounds == 0
    end

    test "delete_user/2 refuse de supprimer son propre compte ou un compte absent" do
      admin = user_fixture()
      assert {:error, :self} = Admin.delete_user(admin, admin.id)
      assert {:error, :not_found} = Admin.delete_user(admin, -1)
    end
  end

  describe "rooms" do
    test "list_rooms/0 et close_room/2 : la room est fermée et ses joueurs prévenus" do
      admin = user_fixture()
      {:ok, code} = Rooms.create_room()
      Rooms.subscribe(code)
      tab = spawn(fn -> Process.sleep(:infinity) end)
      {:ok, _} = Rooms.join(code, %{id: "alice", name: "Alice", user: nil}, tab)

      assert %{code: ^code, players: ["Alice"], status: :lobby} =
               Enum.find(Admin.list_rooms(), &(&1.code == code))

      [{pid, _}] = Registry.lookup(BlindMix.Rooms.Registry, code)
      ref = Process.monitor(pid)

      assert :ok = Admin.close_room(admin, code)
      assert_receive {:room_closed, ^code}
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
      assert {:error, :not_found} = Admin.close_room(admin, code)
      Process.exit(tab, :kill)
    end
  end

  test "stats/0 renvoie les compteurs du site" do
    user_fixture()
    assert %{users: users, rounds: _, plays: _, rooms: _} = Admin.stats()
    assert users >= 1
  end
end
