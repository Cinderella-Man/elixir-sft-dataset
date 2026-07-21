# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
defmodule TeamRouterRoleTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  setup do
    store = start_supervised!({TeamStore, name: :"store_#{System.unique_integer([:positive])}"})

    :ok = TeamStore.create_user(store, "alice", "token-alice")
    :ok = TeamStore.create_user(store, "bob", "token-bob")
    :ok = TeamStore.create_user(store, "carol", "token-carol")
    :ok = TeamStore.create_user(store, "dave", "token-dave")
    :ok = TeamStore.create_user(store, "erin", "token-erin")

    :ok = TeamStore.create_team(store, "team-1")
    :ok = TeamStore.create_team(store, "team-2")

    # team-1: alice owner, bob member, dave admin
    :ok = TeamStore.add_member(store, "team-1", "alice", "owner")
    :ok = TeamStore.add_member(store, "team-1", "bob", "member")
    :ok = TeamStore.add_member(store, "team-1", "dave", "admin")

    # team-2: carol owner
    :ok = TeamStore.add_member(store, "team-2", "carol", "owner")

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

  defp post_member(store, team_id, user_id, token, role \\ nil) do
    payload = if role, do: %{"user_id" => user_id, "role" => role}, else: %{"user_id" => user_id}

    :post
    |> conn("/api/teams/#{team_id}/members", Jason.encode!(payload))
    |> put_req_header("content-type", "application/json")
    |> maybe_auth(token)
    |> put_private(:team_store, store)
    |> TeamRouter.call(TeamRouter.init(store: store))
  end

  defp delete_member(store, team_id, target, token) do
    :delete
    |> conn("/api/teams/#{team_id}/members/#{target}")
    |> maybe_auth(token)
    |> put_private(:team_store, store)
    |> TeamRouter.call(TeamRouter.init(store: store))
  end

  defp maybe_auth(conn, nil), do: conn
  defp maybe_auth(conn, token), do: put_req_header(conn, "authorization", "Bearer #{token}")

  defp json_body(conn), do: Jason.decode!(conn.resp_body)

  defp member(conn, uid) do
    conn |> json_body() |> Map.fetch!("members") |> Enum.find(&(&1["user_id"] == uid))
  end

  # ---------------- GET ----------------

  test "GET returns 200 with roles for a member", %{store: store} do
    conn = get_members(store, "team-1", "token-alice")
    assert conn.status == 200
    assert member(conn, "alice")["role"] == "owner"
    assert member(conn, "bob")["role"] == "member"
    assert member(conn, "dave")["role"] == "admin"
  end

  test "GET is allowed for a plain member", %{store: store} do
    conn = get_members(store, "team-1", "token-bob")
    assert conn.status == 200
    assert member(conn, "alice")["role"] == "owner"
  end

  test "GET returns 403 for a non-member", %{store: store} do
    conn = get_members(store, "team-1", "token-carol")
    assert conn.status == 403
    assert json_body(conn)["error"] == "forbidden"
  end

  test "GET returns 401 without auth", %{store: store} do
    conn = get_members(store, "team-1", nil)
    assert conn.status == 401
    assert json_body(conn)["error"] == "unauthorized"
  end

  test "GET returns 401 with invalid token", %{store: store} do
    conn = get_members(store, "team-1", "token-nobody")
    assert conn.status == 401
  end

  test "GET returns 404 for missing team", %{store: store} do
    conn = get_members(store, "ghost", "token-alice")
    assert conn.status == 404
    assert json_body(conn)["error"] == "not_found"
  end

  # ---------------- POST ----------------

  test "owner can add a new member with default role", %{store: store} do
    conn = post_member(store, "team-1", "carol", "token-alice")
    assert conn.status == 201
    body = json_body(conn)
    assert body["added"] == "carol"
    assert body["role"] == "member"
    assert {:ok, "member"} = TeamStore.role_of(store, "team-1", "carol")
  end

  test "admin can add a new member", %{store: store} do
    conn = post_member(store, "team-1", "erin", "token-dave")
    assert conn.status == 201
    assert TeamStore.is_member?(store, "team-1", "erin")
  end

  test "owner can add a member with an explicit role", %{store: store} do
    conn = post_member(store, "team-1", "erin", "token-alice", "admin")
    assert conn.status == 201
    assert json_body(conn)["role"] == "admin"
    assert {:ok, "admin"} = TeamStore.role_of(store, "team-1", "erin")
  end

  test "plain member cannot add", %{store: store} do
    conn = post_member(store, "team-1", "carol", "token-bob")
    assert conn.status == 403
    assert json_body(conn)["error"] == "forbidden"
  end

  test "non-member cannot add", %{store: store} do
    conn = post_member(store, "team-1", "erin", "token-carol")
    assert conn.status == 403
  end

  test "POST duplicate member returns 409", %{store: store} do
    conn = post_member(store, "team-1", "bob", "token-alice")
    assert conn.status == 409
    assert json_body(conn)["error"] == "conflict"
  end

  test "POST invalid role returns 400", %{store: store} do
    conn = post_member(store, "team-1", "erin", "token-alice", "superuser")
    assert conn.status == 400
    assert json_body(conn)["error"] == "bad_request"
  end

  test "POST missing user_id returns 400", %{store: store} do
    conn =
      :post
      |> conn("/api/teams/team-1/members", Jason.encode!(%{"wrong" => "x"}))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer token-alice")
      |> put_private(:team_store, store)
      |> TeamRouter.call(TeamRouter.init(store: store))

    assert conn.status == 400
  end

  test "POST returns 404 for missing team before role checks", %{store: store} do
    conn = post_member(store, "ghost", "erin", "token-alice")
    assert conn.status == 404
  end

  test "POST returns 401 with invalid token", %{store: store} do
    conn = post_member(store, "team-1", "erin", "token-nobody")
    assert conn.status == 401
  end

  # ---------------- DELETE ----------------

  test "owner can remove a member", %{store: store} do
    conn = delete_member(store, "team-1", "bob", "token-alice")
    assert conn.status == 200
    assert json_body(conn)["removed"] == "bob"
    refute TeamStore.is_member?(store, "team-1", "bob")
  end

  test "admin can remove a plain member", %{store: store} do
    conn = delete_member(store, "team-1", "bob", "token-dave")
    assert conn.status == 200
    refute TeamStore.is_member?(store, "team-1", "bob")
  end

  test "owner can remove an admin", %{store: store} do
    conn = delete_member(store, "team-1", "dave", "token-alice")
    assert conn.status == 200
    refute TeamStore.is_member?(store, "team-1", "dave")
  end

  test "admin cannot remove an owner", %{store: store} do
    conn = delete_member(store, "team-1", "alice", "token-dave")
    assert conn.status == 403
    assert json_body(conn)["error"] == "forbidden"
    assert TeamStore.is_member?(store, "team-1", "alice")
  end

  test "removing a non-member returns 404", %{store: store} do
    conn = delete_member(store, "team-1", "carol", "token-alice")
    assert conn.status == 404
  end

  test "plain member cannot remove", %{store: store} do
    conn = delete_member(store, "team-1", "dave", "token-bob")
    assert conn.status == 403
  end

  test "DELETE returns 404 for missing team", %{store: store} do
    conn = delete_member(store, "ghost", "bob", "token-alice")
    assert conn.status == 404
  end

  test "DELETE returns 401 with invalid token", %{store: store} do
    conn = delete_member(store, "team-1", "bob", "token-nobody")
    assert conn.status == 401
  end

  # ---------------- cross-cutting ----------------

  test "response content-type is application/json", %{store: store} do
    conn = get_members(store, "team-1", "token-alice")
    ct = conn |> get_resp_header("content-type") |> List.first("")
    assert ct =~ "application/json"
  end

  test "operations on team-1 do not affect team-2", %{store: store} do
    _ = post_member(store, "team-1", "carol", "token-alice")
    _ = delete_member(store, "team-1", "bob", "token-alice")

    conn = get_members(store, "team-2", "token-carol")
    assert conn.status == 200
    assert member(conn, "carol")["role"] == "owner"
  end

  # ---------------- AuthPlug.init/1 (runtime-initialized plug) ----------------

  # These directly pin `AuthPlug.init/1`. Because `TeamRouter` initializes
  # its plugs at runtime, a gutted `init/1` (e.g. one that raises or drops its
  # options) is now both compilable and observable — these assertions fail
  # loudly instead of the mutant grading inconclusively.

  test "AuthPlug.init/1 returns its options unchanged" do
    assert AuthPlug.init(store: :some_store) == [store: :some_store]
    assert AuthPlug.init([]) == []
    assert AuthPlug.init(foo: 1, bar: 2) == [foo: 1, bar: 2]
  end

  test "AuthPlug.init/1 output drives authentication when passed to call/2",
       %{store: store} do
    opts = AuthPlug.init(store: store)
    assert opts == [store: store]

    authed =
      :get
      |> conn("/api/teams/team-1/members")
      |> put_req_header("authorization", "Bearer token-alice")
      |> AuthPlug.call(opts)

    refute authed.halted
    assert authed.assigns[:current_user] == "alice"

    rejected =
      :get
      |> conn("/api/teams/team-1/members")
      |> AuthPlug.call(opts)

    assert rejected.halted
    assert rejected.status == 401
  end

  test "router runs AuthPlug.init/1 at request time", %{store: store} do
    # A full request exercises the runtime-initialized AuthPlug pipeline; a
    # gutted init/1 would raise here rather than authenticate cleanly.
    conn = get_members(store, "team-1", "token-alice")
    assert conn.status == 200
    assert member(conn, "alice")["role"] == "owner"
  end

  # ---------------- direct store API ----------------

  test "role_of returns error for non-member", %{store: store} do
    assert :error = TeamStore.role_of(store, "team-1", "carol")
  end

  test "add_member_safe returns conflict for duplicate", %{store: store} do
    assert {:error, :conflict} = TeamStore.add_member_safe(store, "team-1", "alice", "member")
  end

  test "add_member_safe returns not_found for missing team", %{store: store} do
    assert {:error, :not_found} = TeamStore.add_member_safe(store, "nope", "alice", "member")
  end

  test "remove_member_safe returns not_member for absent user", %{store: store} do
    assert {:error, :not_member} = TeamStore.remove_member_safe(store, "team-1", "carol")
  end

  # ---------------- router :store option is load-bearing ----------------

  # `TeamRouter` accepts a `:store` option. These requests carry no other
  # hint about which store to use, so the option alone must locate the
  # `TeamStore` for both the bearer-token lookup and the endpoint handlers.

  defp opts_only_get(store, team_id, token) do
    :get
    |> conn("/api/teams/#{team_id}/members")
    |> maybe_auth(token)
    |> TeamRouter.call(TeamRouter.init(store: store))
  end

  defp opts_only_post(store, team_id, user_id, token) do
    :post
    |> conn("/api/teams/#{team_id}/members", Jason.encode!(%{"user_id" => user_id}))
    |> put_req_header("content-type", "application/json")
    |> maybe_auth(token)
    |> TeamRouter.call(TeamRouter.init(store: store))
  end

  defp opts_only_delete(store, team_id, target, token) do
    :delete
    |> conn("/api/teams/#{team_id}/members/#{target}")
    |> maybe_auth(token)
    |> TeamRouter.call(TeamRouter.init(store: store))
  end

  test "GET reads the roster with the store given only as the :store option", %{store: store} do
    conn = opts_only_get(store, "team-1", "token-alice")
    assert conn.status == 200
    assert member(conn, "alice")["role"] == "owner"
    assert member(conn, "bob")["role"] == "member"
    assert member(conn, "dave")["role"] == "admin"
  end

  test "token lookup uses the store given only as the :store option", %{store: store} do
    conn = opts_only_get(store, "team-1", "token-nobody")
    assert conn.status == 401
    assert json_body(conn)["error"] == "unauthorized"
  end

  test "POST adds a member with the store given only as the :store option", %{store: store} do
    conn = opts_only_post(store, "team-1", "carol", "token-alice")
    assert conn.status == 201
    assert json_body(conn)["added"] == "carol"
    assert {:ok, "member"} = TeamStore.role_of(store, "team-1", "carol")
  end

  test "DELETE removes a member with the store given only as the :store option", %{store: store} do
    conn = opts_only_delete(store, "team-1", "bob", "token-alice")
    assert conn.status == 200
    assert json_body(conn)["removed"] == "bob"
    refute TeamStore.is_member?(store, "team-1", "bob")
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
