defmodule TeamRouterCapacityTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  setup do
    store = start_supervised!({TeamStore, name: :"store_#{System.unique_integer([:positive])}"})

    :ok = TeamStore.create_user(store, "alice", "token-alice")
    :ok = TeamStore.create_user(store, "bob", "token-bob")
    :ok = TeamStore.create_user(store, "carol", "token-carol")
    :ok = TeamStore.create_user(store, "dave", "token-dave")

    for i <- 0..9, do: :ok = TeamStore.create_user(store, "u#{i}", "token-u#{i}")

    :ok = TeamStore.create_team(store, "team-1", 5)
    :ok = TeamStore.create_team(store, "team-2", 5)
    :ok = TeamStore.create_team(store, "team-small", 2)
    :ok = TeamStore.create_team(store, "team-conc", 3)

    :ok = TeamStore.add_member(store, "team-1", "alice")
    :ok = TeamStore.add_member(store, "team-1", "bob")
    :ok = TeamStore.add_member(store, "team-2", "carol")
    :ok = TeamStore.add_member(store, "team-small", "alice")

    %{store: store}
  end

  # ---------------- helpers ----------------

  defp get_members(store, team_id, token) do
    :get
    |> conn("/api/teams/#{team_id}/members")
    |> maybe_auth(token)
    |> put_private(:team_store, store)
    |> TeamRouter.call(TeamRouter.init(store: store))
  end

  defp join(store, team_id, token) do
    :post
    |> conn("/api/teams/#{team_id}/join")
    |> maybe_auth(token)
    |> put_private(:team_store, store)
    |> TeamRouter.call(TeamRouter.init(store: store))
  end

  defp leave(store, team_id, token) do
    :delete
    |> conn("/api/teams/#{team_id}/join")
    |> maybe_auth(token)
    |> put_private(:team_store, store)
    |> TeamRouter.call(TeamRouter.init(store: store))
  end

  defp maybe_auth(conn, nil), do: conn
  defp maybe_auth(conn, token), do: put_req_header(conn, "authorization", "Bearer #{token}")

  defp json_body(conn), do: Jason.decode!(conn.resp_body)

  # ---------------- GET ----------------

  test "GET returns members, size, and capacity", %{store: store} do
    conn = get_members(store, "team-1", "token-alice")
    assert conn.status == 200
    body = json_body(conn)
    assert "alice" in body["members"]
    assert body["size"] == 2
    assert body["capacity"] == 5
  end

  test "GET returns 403 for a non-member", %{store: store} do
    conn = get_members(store, "team-1", "token-carol")
    assert conn.status == 403
    assert json_body(conn)["error"] == "forbidden"
  end

  test "GET returns 401 without auth", %{store: store} do
    conn = get_members(store, "team-1", nil)
    assert conn.status == 401
  end

  test "GET returns 404 for a missing team", %{store: store} do
    conn = get_members(store, "ghost", "token-alice")
    assert conn.status == 404
  end

  # ---------------- join ----------------

  test "join enrolls the caller and reports the new size", %{store: store} do
    conn = join(store, "team-1", "token-dave")
    assert conn.status == 201
    body = json_body(conn)
    assert body["joined"] == "dave"
    assert body["size"] == 3
    assert TeamStore.is_member?(store, "team-1", "dave")
  end

  test "join returns 409 already_member when already enrolled", %{store: store} do
    conn = join(store, "team-1", "token-alice")
    assert conn.status == 409
    assert json_body(conn)["error"] == "already_member"
  end

  test "join returns 409 team_full at capacity", %{store: store} do
    ok = join(store, "team-small", "token-bob")
    assert ok.status == 201
    assert json_body(ok)["size"] == 2

    full = join(store, "team-small", "token-carol")
    assert full.status == 409
    assert json_body(full)["error"] == "team_full"
  end

  test "join returns 404 for a missing team", %{store: store} do
    conn = join(store, "ghost", "token-alice")
    assert conn.status == 404
  end

  test "join returns 401 with an invalid token", %{store: store} do
    conn = join(store, "team-1", "token-nobody")
    assert conn.status == 401
  end

  test "capacity is enforced atomically under concurrent joins", %{store: store} do
    results =
      0..9
      |> Enum.map(fn i -> Task.async(fn -> join(store, "team-conc", "token-u#{i}").status end) end)
      |> Enum.map(&Task.await/1)

    assert Enum.count(results, &(&1 == 201)) == 3
    assert Enum.count(results, &(&1 == 409)) == 7
    assert {:ok, 3} = TeamStore.size(store, "team-conc")
  end

  # ---------------- leave ----------------

  test "leave withdraws the caller and reports the new size", %{store: store} do
    conn = leave(store, "team-1", "token-alice")
    assert conn.status == 200
    body = json_body(conn)
    assert body["left"] == "alice"
    assert body["size"] == 1
    refute TeamStore.is_member?(store, "team-1", "alice")
  end

  test "leaving frees a slot for a new join", %{store: store} do
    full = join(store, "team-small", "token-bob")
    assert full.status == 201

    blocked = join(store, "team-small", "token-carol")
    assert blocked.status == 409

    _ = leave(store, "team-small", "token-alice")

    retry = join(store, "team-small", "token-carol")
    assert retry.status == 201
    assert {:ok, 2} = TeamStore.size(store, "team-small")
  end

  test "leave returns 409 not_member when not enrolled", %{store: store} do
    conn = leave(store, "team-1", "token-carol")
    assert conn.status == 409
    assert json_body(conn)["error"] == "not_member"
  end

  test "leave returns 404 for a missing team", %{store: store} do
    conn = leave(store, "ghost", "token-alice")
    assert conn.status == 404
  end

  # ---------------- cross-cutting ----------------

  test "response content-type is application/json", %{store: store} do
    conn = get_members(store, "team-1", "token-alice")
    ct = conn |> get_resp_header("content-type") |> List.first("")
    assert ct =~ "application/json"
  end

  test "operations on team-1 do not affect team-2", %{store: store} do
    _ = join(store, "team-1", "token-dave")
    conn = get_members(store, "team-2", "token-carol")
    assert json_body(conn)["members"] == ["carol"]
    assert json_body(conn)["size"] == 1
  end

  # ---------------- direct store API ----------------

  test "join_safe reports full at capacity", %{store: store} do
    assert {:ok, "bob", 2} = TeamStore.join_safe(store, "team-small", "bob")
    assert {:error, :full} = TeamStore.join_safe(store, "team-small", "carol")
  end

  test "join_safe reports already_member", %{store: store} do
    assert {:error, :already_member} = TeamStore.join_safe(store, "team-1", "alice")
  end

  test "join_safe reports not_found for a missing team", %{store: store} do
    assert {:error, :not_found} = TeamStore.join_safe(store, "nope", "alice")
  end

  test "leave_safe reports not_member", %{store: store} do
    assert {:error, :not_member} = TeamStore.leave_safe(store, "team-1", "carol")
  end

  test "capacity and size expose team state", %{store: store} do
    assert {:ok, 5} = TeamStore.capacity(store, "team-1")
    assert {:ok, 2} = TeamStore.size(store, "team-1")
  end
end

defmodule TeamStoreInitTest do
  # Deliberately NO shared setup: this module starts its own store inside the
  # test body so that a gutted `init/1` surfaces as a clean, fast assertion
  # failure here rather than an ambiguous setup crash. This directly exercises
  # the empty tokens/teams state that `init/1` is responsible for producing.
  use ExUnit.Case, async: false

  test "init/1 starts a live process backed by a well-formed empty store" do
    name = :"init_store_#{System.unique_integer([:positive])}"

    # A raise-gutted init/1 makes start_link return {:error, _}; the caller is
    # not killed (proc_lib exits the failed child as :normal), so this match
    # fails cleanly and fast, killing the mutant.
    assert {:ok, pid} = TeamStore.start_link(name: name)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

    assert Process.alive?(pid)

    # The freshly-initialized state must be empty and answer calls correctly.
    assert :error = TeamStore.get_user_by_token(pid, "no-such-token")
    refute TeamStore.team_exists?(pid, "ghost")
    assert :error = TeamStore.capacity(pid, "ghost")
    assert :error = TeamStore.size(pid, "ghost")
    assert {:error, :not_found} = TeamStore.list_members(pid, "ghost")
    assert {:error, :not_found} = TeamStore.join_safe(pid, "ghost", "nobody")

    # And the store must be fully usable after init: seed and drive the flow.
    :ok = TeamStore.create_user(pid, "zoe", "tok-zoe")
    assert {:ok, "zoe"} = TeamStore.get_user_by_token(pid, "tok-zoe")

    :ok = TeamStore.create_team(pid, "solo", 1)
    assert TeamStore.team_exists?(pid, "solo")
    assert {:ok, 1} = TeamStore.capacity(pid, "solo")
    assert {:ok, 0} = TeamStore.size(pid, "solo")

    assert {:ok, "zoe", 1} = TeamStore.join_safe(pid, "solo", "zoe")
    assert {:ok, ["zoe"]} = TeamStore.list_members(pid, "solo")
    assert {:error, :full} = TeamStore.join_safe(pid, "solo", "yan")
  end
end