defmodule TeamRouterEtagTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  setup do
    store = start_supervised!({TeamStore, name: :"store_#{System.unique_integer([:positive])}"})

    :ok = TeamStore.create_user(store, "alice", "token-alice")
    :ok = TeamStore.create_user(store, "bob", "token-bob")
    :ok = TeamStore.create_user(store, "carol", "token-carol")

    :ok = TeamStore.create_team(store, "team-1")
    :ok = TeamStore.create_team(store, "team-2")

    # team-1 -> version 2 after two seeds
    :ok = TeamStore.add_member(store, "team-1", "alice")
    :ok = TeamStore.add_member(store, "team-1", "bob")
    # team-2 -> version 1
    :ok = TeamStore.add_member(store, "team-2", "carol")

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

  defp post_member(store, team_id, user_id, token, if_match) do
    :post
    |> conn("/api/teams/#{team_id}/members", Jason.encode!(%{"user_id" => user_id}))
    |> put_req_header("content-type", "application/json")
    |> maybe_auth(token)
    |> maybe_if_match(if_match)
    |> put_private(:team_store, store)
    |> TeamRouter.call(TeamRouter.init(store: store))
  end

  defp maybe_auth(conn, nil), do: conn
  defp maybe_auth(conn, token), do: put_req_header(conn, "authorization", "Bearer #{token}")

  defp maybe_if_match(conn, nil), do: conn
  defp maybe_if_match(conn, v), do: put_req_header(conn, "if-match", v)

  defp json_body(conn), do: Jason.decode!(conn.resp_body)

  defp etag(conn), do: conn |> get_resp_header("etag") |> List.first()

  # ---------------- GET ----------------

  test "GET returns members, version, and an ETag header", %{store: store} do
    conn = get_members(store, "team-1", "token-alice")
    assert conn.status == 200
    body = json_body(conn)
    assert "alice" in body["members"]
    assert "bob" in body["members"]
    assert body["version"] == 2
    assert etag(conn) == ~s("2")
  end

  test "ETag matches the reported version", %{store: store} do
    conn = get_members(store, "team-2", "token-carol")
    assert json_body(conn)["version"] == 1
    assert etag(conn) == ~s("1")
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

  # ---------------- POST optimistic concurrency ----------------

  test "POST with correct If-Match succeeds and bumps the version", %{store: store} do
    conn = post_member(store, "team-1", "carol", "token-alice", ~s("2"))
    assert conn.status == 201
    body = json_body(conn)
    assert body["added"] == "carol"
    assert body["version"] == 3
    assert etag(conn) == ~s("3")
    assert {:ok, 3} = TeamStore.version(store, "team-1")
  end

  test "bare (unquoted) If-Match is accepted", %{store: store} do
    conn = post_member(store, "team-1", "carol", "token-alice", "2")
    assert conn.status == 201
    assert json_body(conn)["version"] == 3
  end

  test "added member and new version appear in a subsequent GET", %{store: store} do
    _ = post_member(store, "team-1", "carol", "token-alice", ~s("2"))
    conn = get_members(store, "team-1", "token-alice")
    assert "carol" in json_body(conn)["members"]
    assert json_body(conn)["version"] == 3
  end

  test "stale If-Match returns 412", %{store: store} do
    conn1 = post_member(store, "team-1", "carol", "token-alice", ~s("2"))
    assert conn1.status == 201

    conn2 = post_member(store, "team-1", "dave", "token-alice", ~s("2"))
    assert conn2.status == 412
    assert json_body(conn2)["error"] == "precondition_failed"
  end

  test "missing If-Match returns 428", %{store: store} do
    conn = post_member(store, "team-1", "carol", "token-alice", nil)
    assert conn.status == 428
    assert json_body(conn)["error"] == "precondition_required"
  end

  test "duplicate member with matching version returns 409", %{store: store} do
    conn = post_member(store, "team-1", "bob", "token-alice", ~s("2"))
    assert conn.status == 409
    assert json_body(conn)["error"] == "conflict"
  end

  test "non-member gets 403 before any precondition check", %{store: store} do
    conn = post_member(store, "team-1", "dave", "token-carol", nil)
    assert conn.status == 403
  end

  test "missing team gets 404 before any precondition check", %{store: store} do
    conn = post_member(store, "ghost", "dave", "token-alice", nil)
    assert conn.status == 404
  end

  test "POST returns 401 with invalid token", %{store: store} do
    conn = post_member(store, "team-1", "carol", "token-nobody", ~s("2"))
    assert conn.status == 401
  end

  test "malformed body with valid precondition returns 400", %{store: store} do
    conn =
      :post
      |> conn("/api/teams/team-1/members", Jason.encode!(%{"nope" => "x"}))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer token-alice")
      |> put_req_header("if-match", ~s("2"))
      |> put_private(:team_store, store)
      |> TeamRouter.call(TeamRouter.init(store: store))

    assert conn.status == 400
  end

  # ---------------- cross-cutting ----------------

  test "response content-type is application/json", %{store: store} do
    conn = get_members(store, "team-1", "token-alice")
    ct = conn |> get_resp_header("content-type") |> List.first("")
    assert ct =~ "application/json"
  end

  test "operations on team-1 do not affect team-2", %{store: store} do
    _ = post_member(store, "team-1", "carol", "token-alice", ~s("2"))
    conn = get_members(store, "team-2", "token-carol")
    assert json_body(conn)["members"] == ["carol"]
    assert json_body(conn)["version"] == 1
  end

  # ---------------- direct store API ----------------

  test "version returns the current team version", %{store: store} do
    assert {:ok, 2} = TeamStore.version(store, "team-1")
  end

  test "add_member_safe reports version_mismatch with the current version", %{store: store} do
    assert {:error, :version_mismatch, 2} =
             TeamStore.add_member_safe(store, "team-1", "carol", 99)
  end

  test "add_member_safe reports conflict when version matches", %{store: store} do
    assert {:error, :conflict} = TeamStore.add_member_safe(store, "team-1", "alice", 2)
  end

  test "add_member_safe reports not_found for a missing team", %{store: store} do
    assert {:error, :not_found} = TeamStore.add_member_safe(store, "nope", "alice", 0)
  end
end