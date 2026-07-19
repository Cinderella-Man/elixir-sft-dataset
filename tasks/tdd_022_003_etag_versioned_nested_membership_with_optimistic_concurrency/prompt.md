# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
defmodule TeamRouterOptimisticTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  setup do
    store = start_supervised!({TeamStore, name: :"store_#{System.unique_integer([:positive])}"})

    :ok = TeamStore.create_user(store, "alice", "token-alice")
    :ok = TeamStore.create_user(store, "bob", "token-bob")
    :ok = TeamStore.create_user(store, "carol", "token-carol")
    :ok = TeamStore.create_user(store, "dave", "token-dave")

    :ok = TeamStore.create_team(store, "team-1")
    :ok = TeamStore.create_team(store, "team-2")

    :ok = TeamStore.add_member(store, "team-1", "alice")
    :ok = TeamStore.add_member(store, "team-1", "bob")
    :ok = TeamStore.add_member(store, "team-2", "carol")

    %{store: store}
  end

  # -------------------------------------------------------
  # Helpers
  # -------------------------------------------------------

  defp get_members(store, team_id, token) do
    :get
    |> conn("/api/teams/#{team_id}/members")
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_private(:team_store, store)
    |> TeamRouter.call(TeamRouter.init(store: store))
  end

  defp post_member(store, team_id, user_id, token, if_match) do
    body = Jason.encode!(%{"user_id" => user_id})

    :post
    |> conn("/api/teams/#{team_id}/members", body)
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("if-match", if_match)
    |> put_private(:team_store, store)
    |> TeamRouter.call(TeamRouter.init(store: store))
  end

  defp post_member_no_match(store, team_id, user_id, token) do
    body = Jason.encode!(%{"user_id" => user_id})

    :post
    |> conn("/api/teams/#{team_id}/members", body)
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("content-type", "application/json")
    |> put_private(:team_store, store)
    |> TeamRouter.call(TeamRouter.init(store: store))
  end

  defp json_body(conn), do: Jason.decode!(conn.resp_body)

  defp etag(conn), do: conn |> get_resp_header("etag") |> List.first()

  defp version(store, team_id) do
    {:ok, v} = TeamStore.get_version(store, team_id)
    v
  end

  # -------------------------------------------------------
  # GET — happy path + versioning
  # -------------------------------------------------------

  test "GET returns 200 with members, version and ETag header", %{store: store} do
    v = version(store, "team-1")
    conn = get_members(store, "team-1", "token-alice")

    assert conn.status == 200
    body = json_body(conn)
    assert "alice" in body["members"]
    assert "bob" in body["members"]
    refute "carol" in body["members"]
    assert body["version"] == v
    assert etag(conn) == to_string(v)
  end

  test "GET returns 200 for any member", %{store: store} do
    conn = get_members(store, "team-1", "token-bob")
    assert conn.status == 200
    assert "alice" in json_body(conn)["members"]
  end

  # -------------------------------------------------------
  # GET — authorization / not found
  # -------------------------------------------------------

  test "GET returns 403 when user is not a member", %{store: store} do
    conn = get_members(store, "team-1", "token-carol")
    assert conn.status == 403
    assert json_body(conn)["error"] == "forbidden"
  end

  test "GET returns 401 with missing auth header", %{store: store} do
    conn =
      :get
      |> conn("/api/teams/team-1/members")
      |> put_private(:team_store, store)
      |> TeamRouter.call(TeamRouter.init(store: store))

    assert conn.status == 401
    assert json_body(conn)["error"] == "unauthorized"
  end

  test "GET returns 401 with invalid token", %{store: store} do
    conn = get_members(store, "team-1", "token-nobody")
    assert conn.status == 401
  end

  test "GET returns 404 for non-existent team", %{store: store} do
    conn = get_members(store, "no-such-team", "token-alice")
    assert conn.status == 404
    assert json_body(conn)["error"] == "not_found"
  end

  # -------------------------------------------------------
  # POST — happy path bumps version
  # -------------------------------------------------------

  test "POST with matching If-Match returns 201 and increments version", %{store: store} do
    v = version(store, "team-1")
    conn = post_member(store, "team-1", "carol", "token-alice", to_string(v))

    assert conn.status == 201
    body = json_body(conn)
    assert body["added"] == "carol"
    assert body["version"] == v + 1
    assert etag(conn) == to_string(v + 1)
    assert TeamStore.is_member?(store, "team-1", "carol")
  end

  test "POST newly added member appears in subsequent GET", %{store: store} do
    v = version(store, "team-1")
    post_member(store, "team-1", "carol", "token-alice", to_string(v))

    conn = get_members(store, "team-1", "token-alice")
    assert "carol" in json_body(conn)["members"]
  end

  # -------------------------------------------------------
  # POST — precondition semantics
  # -------------------------------------------------------

  test "POST without If-Match header returns 428", %{store: store} do
    conn = post_member_no_match(store, "team-1", "carol", "token-alice")
    assert conn.status == 428
    assert json_body(conn)["error"] == "precondition_required"
  end

  test "POST with stale If-Match returns 412", %{store: store} do
    v = version(store, "team-1")
    # First write succeeds and moves the version forward.
    assert post_member(store, "team-1", "carol", "token-alice", to_string(v)).status == 201
    # Second write still presenting the old version is rejected.
    conn = post_member(store, "team-1", "dave", "token-alice", to_string(v))
    assert conn.status == 412
    assert json_body(conn)["error"] == "precondition_failed"
  end

  test "optimistic concurrency: two writers with the same base version, second is stale", %{
    store: store
  } do
    v = version(store, "team-1")
    c1 = post_member(store, "team-1", "carol", "token-alice", to_string(v))
    c2 = post_member(store, "team-1", "dave", "token-alice", to_string(v))
    assert c1.status == 201
    assert c2.status == 412
  end

  test "POST with matching If-Match but duplicate member returns 409", %{store: store} do
    v = version(store, "team-1")
    conn = post_member(store, "team-1", "bob", "token-alice", to_string(v))
    assert conn.status == 409
    assert json_body(conn)["error"] == "conflict"
  end

  # -------------------------------------------------------
  # POST — a non-integer If-Match can never match a version
  # -------------------------------------------------------

  test "POST with a non-numeric If-Match returns 412 and writes nothing", %{store: store} do
    v = version(store, "team-1")
    conn = post_member(store, "team-1", "carol", "token-alice", "abc")

    assert conn.status == 412
    assert json_body(conn)["error"] == "precondition_failed"
    refute TeamStore.is_member?(store, "team-1", "carol")
    assert version(store, "team-1") == v
  end

  test "POST with a trailing-garbage If-Match returns 412 even at the live version", %{
    store: store
  } do
    v = version(store, "team-1")
    conn = post_member(store, "team-1", "carol", "token-alice", "#{v}x")

    assert conn.status == 412
    assert json_body(conn)["error"] == "precondition_failed"
    refute TeamStore.is_member?(store, "team-1", "carol")
    assert version(store, "team-1") == v
  end

  # -------------------------------------------------------
  # POST — authorization / not found / bad request
  # -------------------------------------------------------

  test "POST returns 403 when user is not a member", %{store: store} do
    v = version(store, "team-1")
    conn = post_member(store, "team-1", "carol", "token-carol", to_string(v))
    assert conn.status == 403
    assert json_body(conn)["error"] == "forbidden"
  end

  test "POST returns 401 with invalid token", %{store: store} do
    conn = post_member(store, "team-1", "carol", "token-nobody", "0")
    assert conn.status == 401
  end

  test "POST returns 404 for non-existent team", %{store: store} do
    conn = post_member(store, "no-such-team", "carol", "token-alice", "0")
    assert conn.status == 404
    assert json_body(conn)["error"] == "not_found"
  end

  test "POST with malformed body returns 400", %{store: store} do
    v = version(store, "team-1")
    body = Jason.encode!(%{"wrong_field" => "carol"})

    conn =
      :post
      |> conn("/api/teams/team-1/members", body)
      |> put_req_header("authorization", "Bearer token-alice")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("if-match", to_string(v))
      |> put_private(:team_store, store)
      |> TeamRouter.call(TeamRouter.init(store: store))

    assert conn.status == 400
  end

  # -------------------------------------------------------
  # Content type / isolation
  # -------------------------------------------------------

  test "response content-type is application/json", %{store: store} do
    conn = get_members(store, "team-1", "token-alice")

    content_type =
      conn
      |> get_resp_header("content-type")
      |> List.first("")

    assert content_type =~ "application/json"
  end

  test "operations on team-1 do not affect team-2", %{store: store} do
    v = version(store, "team-1")
    post_member(store, "team-1", "carol", "token-alice", to_string(v))

    conn = get_members(store, "team-2", "token-carol")
    assert conn.status == 200
    assert json_body(conn)["members"] == ["carol"]
  end

  # -------------------------------------------------------
  # Absolute version numbering starts at 0
  # -------------------------------------------------------

  test "a freshly created team has no members and version 0", %{store: store} do
    :ok = TeamStore.create_team(store, "team-fresh")

    assert {:ok, 0} = TeamStore.get_version(store, "team-fresh")
    assert {:ok, []} = TeamStore.list_members(store, "team-fresh")
  end

  test "versions counted from 0 are client-visible: seed yields 1, then POST yields 2", %{
    store: store
  } do
    :ok = TeamStore.create_team(store, "team-fresh")
    :ok = TeamStore.add_member(store, "team-fresh", "alice")

    read = get_members(store, "team-fresh", "token-alice")
    assert read.status == 200
    assert json_body(read)["version"] == 1
    assert etag(read) == "1"

    write = post_member(store, "team-fresh", "bob", "token-alice", "1")
    assert write.status == 201
    assert json_body(write)["version"] == 2
    assert etag(write) == "2"
  end

  # -------------------------------------------------------
  # TeamStore direct API verification
  # -------------------------------------------------------

  test "TeamStore.get_version returns not_found for unknown team", %{store: store} do
    assert {:error, :not_found} = TeamStore.get_version(store, "nope")
  end

  test "TeamStore.list_members returns not_found for unknown team", %{store: store} do
    assert {:error, :not_found} = TeamStore.list_members(store, "nope")
  end

  test "TeamStore.add_member_safe returns stale on version mismatch", %{store: store} do
    assert {:error, :stale} = TeamStore.add_member_safe(store, "team-1", "carol", 999)
  end

  test "TeamStore.add_member_safe returns conflict for duplicate at matching version", %{
    store: store
  } do
    v = version(store, "team-1")
    assert {:error, :conflict} = TeamStore.add_member_safe(store, "team-1", "alice", v)
  end

  test "TeamStore.add_member_safe returns not_found for missing team", %{store: store} do
    assert {:error, :not_found} = TeamStore.add_member_safe(store, "nope", "alice", 0)
  end

  test "TeamStore.add_member_safe returns ok with new version on success", %{store: store} do
    v = version(store, "team-2")
    assert {:ok, "dave", nv} = TeamStore.add_member_safe(store, "team-2", "dave", v)
    assert nv == v + 1
  end

  test "TeamStore.get_user_by_token returns error for unknown token", %{store: store} do
    assert :error = TeamStore.get_user_by_token(store, "bogus")
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
