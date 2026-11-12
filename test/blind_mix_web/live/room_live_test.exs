defmodule BlindMixWeb.RoomLiveTest do
  # Les rooms sont des processus partagés qui écrivent en base : pas de tests en parallèle.
  use BlindMixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias BlindMix.Rooms

  defp room_pid(code) do
    [{pid, _}] = Registry.lookup(BlindMix.Rooms.Registry, code)
    pid
  end

  # Garantit que les vues ont reçu le dernier état diffusé par la room.
  defp sync(code), do: _ = :sys.get_state(room_pid(code))

  defp anonymous(conn, id, name) do
    Phoenix.ConnTest.init_test_session(conn, %{"player_id" => id, "player_name" => name})
  end

  defp new_room do
    {:ok, code} = Rooms.create_room()

    on_exit(fn ->
      for {pid, _} <- Registry.lookup(BlindMix.Rooms.Registry, code) do
        try do
          GenServer.stop(pid)
        catch
          :exit, _ -> :ok
        end
      end
    end)

    code
  end

  describe "entrée dans une room" do
    test "créer une room y emmène, en passant par le choix du pseudo", %{conn: conn} do
      conn = post(conn, ~p"/rooms")
      assert "/rooms/" <> code = redirected_to(conn)
      on_exit(fn -> if Rooms.exists?(code), do: GenServer.stop(room_pid(code)) end)

      assert {:error, {:redirect, %{to: join_path}}} = live(recycle(conn), ~p"/rooms/#{code}")
      assert join_path == "/rooms/#{code}/join"

      conn = post(recycle(conn), join_path, %{"player" => %{"name" => "Alice"}})
      assert redirected_to(conn) == "/rooms/#{code}"
      assert get_session(conn, :player_name) == "Alice"

      {:ok, view, _html} = live(recycle(conn), ~p"/rooms/#{code}")
      assert has_element?(view, "#room-code", code)
      assert has_element?(view, "#room-players .bm-player--me", "Alice")
      assert has_element?(view, "#start-round")
    end

    test "un pseudo vide est refusé", %{conn: conn} do
      code = new_room()
      conn = post(conn, ~p"/rooms/#{code}/join", %{"player" => %{"name" => "   "}})
      assert html_response(conn, 422) =~ "room-join-form"
    end

    test "rejoindre par code (minuscules acceptées), ou code inconnu", %{conn: conn} do
      code = new_room()

      assert redirected_to(get(conn, ~p"/rooms/join?code=#{String.downcase(code)}")) ==
               "/rooms/#{code}"

      conn = get(conn, ~p"/rooms/join?code=ZZZZZ")
      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Aucune room"
    end

    test "une room inconnue renvoie à l'accueil", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} =
               live(anonymous(conn, "p1", "Alice"), ~p"/rooms/ZZZZZ")
    end

    test "un joueur connecté entre directement, sous le début de son e-mail", %{conn: conn} do
      %{conn: conn, user: user} = register_and_log_in_user(%{conn: conn})
      code = new_room()

      {:ok, view, _html} = live(conn, ~p"/rooms/#{code}")
      name = user.email |> String.split("@") |> hd()
      assert has_element?(view, "#player-u-#{user.id}", name)
    end
  end

  describe "partie à deux" do
    setup %{conn: conn} do
      code = new_room()
      Rooms.subscribe(code)

      {:ok, alice, _} = live(anonymous(conn, "alice", "Alice"), ~p"/rooms/#{code}")
      {:ok, bob, _} = live(anonymous(build_conn(), "bob", "Bob"), ~p"/rooms/#{code}")
      sync(code)

      %{code: code, alice: alice, bob: bob}
    end

    test "seul l'hôte lance la manche, les autres attendent", %{alice: alice, bob: bob} do
      assert has_element?(alice, "#start-round")
      refute has_element?(bob, "#start-round")
      assert has_element?(bob, "#room-waiting", "Alice")
    end

    test "course : la piste trouvée par Bob est révélée chez Alice", ctx do
      %{code: code, alice: alice, bob: bob} = ctx

      alice |> element("#start-round") |> render_click()
      assert_receive {:room, %{status: :playing}}, 2_000
      sync(code)

      assert has_element?(alice, "#room-guess-form")
      assert has_element?(bob, "#room-guess-form")

      [track | _] = :sys.get_state(room_pid(code)).game.tracks
      bob |> form("#room-guess-form", %{"guess" => track.title}) |> render_submit()
      sync(code)

      assert has_element?(alice, "#slot-#{track.id}.bm-slot--title", "Bob")
      assert has_element?(alice, "#player-bob", "5")
      assert has_element?(bob, ".bm-feedback", "Bien joué")

      alice |> form("#room-guess-form", %{"guess" => "pas du tout"}) |> render_submit()
      assert has_element?(alice, ".bm-feedback", "Raté")
    end

    test "les boutons de dev apparaissent en mode dev", %{code: code, alice: alice} do
      previous = Application.get_env(:blind_mix, :dev_routes)
      Application.put_env(:blind_mix, :dev_routes, true)
      on_exit(fn -> Application.put_env(:blind_mix, :dev_routes, previous) end)

      {:ok, dev, _html} = live(anonymous(build_conn(), "dev", "Dev"), ~p"/rooms/#{code}")
      alice |> element("#start-round") |> render_click()
      assert_receive {:room, %{status: :playing}}, 2_000
      sync(code)

      [track | _] = :sys.get_state(room_pid(code)).game.tracks
      assert has_element?(dev, "#dev-finish")
      refute has_element?(alice, "#dev-finish")

      dev |> element("#dev-title-#{track.id}") |> render_click()
      sync(code)
      assert has_element?(alice, "#slot-#{track.id}.bm-slot--title", "Dev")

      dev |> element("#dev-finish") |> render_click()
      assert_receive {:room, %{status: :finished}}, 2_000
    end

    test "le bouton « Je suis prêt » est visible de tous", %{code: code, alice: alice, bob: bob} do
      bob |> element("#room-ready") |> render_click()
      sync(code)
      assert has_element?(alice, "#player-bob", "prêt")
    end
  end

  describe "likes du service musical" do
    test "les likes du service connecté sont ajoutés à la room", %{conn: conn} do
      code = new_room()

      conn =
        conn
        |> anonymous("carol", "Carol")
        |> Plug.Conn.put_session(:provider, "fake")
        |> Plug.Conn.put_session(:access_token, "fake-token")

      {:ok, view, _html} = live(conn, ~p"/rooms/#{code}")
      render_async(view)
      sync(code)

      assert has_element?(view, "#player-carol", "5 likes")
    end

    test "le retour OAuth ramène dans la room, jamais ailleurs", %{conn: conn} do
      code = new_room()

      conn = get(conn, ~p"/auth/fake?#{[return_to: "/rooms/#{code}"]}")
      assert get_session(conn, :oauth_return_to) == "/rooms/#{code}"

      state = get_session(conn, :oauth_state)
      conn = get(recycle(conn), ~p"/auth/fake/callback?#{[code: "fake", state: state]}")
      assert redirected_to(conn) == "/rooms/#{code}"

      conn = get(build_conn(), ~p"/auth/fake?#{[return_to: "https://evil.example"]}")
      refute get_session(conn, :oauth_return_to)
    end
  end
end
