defmodule BlindMix.Rooms.ServerTest do
  # Le processus de room écrit en base (historique) : bac à sable partagé, pas d'async.
  use BlindMix.DataCase, async: false

  import BlindMix.AccountsFixtures

  alias BlindMix.{History, Rooms}
  alias BlindMix.Accounts.Scope

  defp t(id, title, artist), do: %{id: id, title: title, artist: artist, preview_url: nil}

  # Un « onglet » de joueur : un processus qui vit jusqu'à ce qu'on l'arrête.
  defp tab do
    spawn(fn ->
      receive do
        :close -> :ok
      end
    end)
  end

  defp room_pid(code) do
    [{pid, _}] = Registry.lookup(BlindMix.Rooms.Registry, code)
    pid
  end

  defp stop_room(code) do
    for {pid, _} <- Registry.lookup(BlindMix.Rooms.Registry, code) do
      try do
        GenServer.stop(pid)
      catch
        :exit, _ -> :ok
      end
    end
  end

  defp round_tracks(code), do: :sys.get_state(room_pid(code)).game.tracks

  defp await_status(status) do
    assert_receive {:room, %{status: ^status} = state}, 2_000
    state
  end

  defp start_round(code, host_id) do
    assert :ok = Rooms.start_round(code, host_id)
    await_status(:playing)
  end

  setup do
    {:ok, code} = Rooms.create_room()
    Rooms.subscribe(code)
    on_exit(fn -> stop_room(code) end)
    %{code: code}
  end

  test "le premier arrivé est l'hôte, les suivants le voient", %{code: code} do
    assert {:ok, %{host_id: "alice"}} =
             Rooms.join(code, %{id: "alice", name: "Alice", user: nil}, tab())

    assert {:ok, state} = Rooms.join(code, %{id: "bob", name: "Bob", user: nil}, tab())

    assert state.host_id == "alice"
    assert Enum.map(state.players, & &1.name) |> Enum.sort() == ["Alice", "Bob"]
  end

  test "une room inconnue répond :not_found" do
    assert {:error, :not_found} = Rooms.join("ZZZZZ", %{id: "x", name: "X", user: nil}, tab())
  end

  test "course : le premier qui trouve marque, les titres restent secrets avant", %{code: code} do
    Rooms.join(code, %{id: "alice", name: "Alice", user: nil}, tab())
    Rooms.join(code, %{id: "bob", name: "Bob", user: nil}, tab())

    assert {:error, :not_allowed} = Rooms.start_round(code, "bob")
    state = start_round(code, "alice")

    assert length(state.audio) == 5
    assert Enum.all?(state.slots, &(is_nil(&1.title) and is_nil(&1.artist)))

    [first | _] = round_tracks(code)
    assert {:ok, [{:title, _, 5}]} = Rooms.guess(code, "bob", first.title)
    assert {:ok, []} = Rooms.guess(code, "alice", first.title)
    assert {:ok, []} = Rooms.guess(code, "alice", "rien à voir")

    state = Rooms.state(code)
    slot = Enum.find(state.slots, &(&1.id == first.id))
    assert %{state: :title, finder: "Bob", title: title} = slot
    assert title == first.title
    assert length(state.audio) == 4
    assert Enum.find(state.players, &(&1.id == "bob")).score == 5
  end

  test "les morceaux likés en commun passent en priorité", %{code: code} do
    shared = for i <- 1..5, do: t("s#{i}", "Commun #{i}", "Groupe #{i}")
    Rooms.join(code, %{id: "alice", name: "Alice", user: nil}, tab())
    Rooms.join(code, %{id: "bob", name: "Bob", user: nil}, tab())
    :ok = Rooms.set_likes(code, "alice", {:ready, shared ++ [t("a", "Solo", "A")], "deezer"})
    :ok = Rooms.set_likes(code, "bob", {:ready, shared, "spotify"})

    assert Rooms.state(code).common_count == 5
    start_round(code, "alice")

    tracks = round_tracks(code)
    assert Enum.all?(tracks, &(&1.origin == :common))
    assert tracks |> Enum.map(& &1.owners) |> Enum.uniq() == [["alice", "bob"]]
  end

  test "fin de manche : historique pour les connectés, recherche élargie", %{code: code} do
    user = user_fixture()
    Rooms.join(code, %{id: "u-#{user.id}", name: "Alice", user: user}, tab())
    Rooms.join(code, %{id: "anon", name: "Anonyme", user: nil}, tab())
    start_round(code, "u-#{user.id}")

    [first | others] = round_tracks(code)
    Rooms.guess(code, "u-#{user.id}", first.title)
    for track <- others, do: Rooms.guess(code, "anon", track.title)

    state = await_status(:finished)
    assert Enum.all?(state.slots, &(&1.state == :title))

    # L'historique ne garde que ce que ce joueur a trouvé lui-même.
    assert [round] = History.list_rounds(Scope.for_user(user))
    assert round.provider == "room"
    assert Enum.count(round.plays, &(&1.result == :title)) == 1

    # Le profil de l'anonyme vit dans la room, et la recherche s'élargit.
    room = :sys.get_state(room_pid(code))
    artists = Map.values(room.players["anon"].taste.artists)
    assert length(artists) == 5
    assert artists |> Enum.map(& &1.found) |> Enum.sum() == 4
    assert Enum.any?(room.pool, &String.contains?(&1.id, "-more"))
  end

  test "si l'hôte part, le joueur suivant prend la main", %{code: code} do
    host_tab = tab()
    Rooms.join(code, %{id: "alice", name: "Alice", user: nil}, host_tab)
    Rooms.join(code, %{id: "bob", name: "Bob", user: nil}, tab())

    send(host_tab, :close)
    assert_receive {:room, %{host_id: "bob"}}, 1_000
  end

  describe "outils de développement" do
    setup %{code: code} do
      Rooms.join(code, %{id: "alice", name: "Alice", user: nil}, tab())
      Rooms.join(code, %{id: "bob", name: "Bob", user: nil}, tab())
      :ok
    end

    test "refusés hors mode dev", %{code: code} do
      start_round(code, "alice")
      [track | _] = round_tracks(code)

      assert {:error, :not_allowed} = Rooms.dev_found(code, "bob", track.id, :title)
      assert {:error, :not_allowed} = Rooms.dev_finish(code)
      assert Rooms.state(code).status == :playing
    end

    test "en mode dev : piste créditée au joueur, puis fin de manche", %{code: code} do
      previous = Application.get_env(:blind_mix, :dev_routes)
      Application.put_env(:blind_mix, :dev_routes, true)
      on_exit(fn -> Application.put_env(:blind_mix, :dev_routes, previous) end)

      start_round(code, "alice")
      [track | _] = round_tracks(code)

      assert :ok = Rooms.dev_found(code, "bob", track.id, :artist)
      slot = Enum.find(Rooms.state(code).slots, &(&1.id == track.id))
      assert %{state: :artist, finder: "Bob"} = slot

      assert :ok = Rooms.dev_finish(code)
      state = await_status(:finished)
      assert Enum.count(state.slots, &(&1.state == :missed)) == 4
    end
  end

  test "une room vide finit par s'arrêter" do
    Application.put_env(:blind_mix, :room_idle_ms, 50)
    on_exit(fn -> Application.delete_env(:blind_mix, :room_idle_ms) end)

    {:ok, code} = Rooms.create_room()
    ref = Process.monitor(room_pid(code))
    assert_receive {:DOWN, ^ref, :process, _, :normal}, 1_000
    assert {:error, :not_found} = Rooms.state(code)
  end
end
