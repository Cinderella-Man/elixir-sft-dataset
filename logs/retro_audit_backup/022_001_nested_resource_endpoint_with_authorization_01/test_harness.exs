defmodule TeamRouterTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  setup do
    store = start_supervised!({TeamStore, name: :"store_#{System.unique_integer([:positive])}"})

    # Seed users
    :ok = TeamStore.create_user(store, "alice", "token-alice")
    :ok = TeamStore.create_user(store, "bob", "token-bob")
    :ok = TeamStore.create_user(store, "carol", "token-carol")

    # Seed teams
    :ok = TeamStore.create_team(store, "team-1")
    :ok = TeamStore.create_team(store, "team-2")

    # alice and bob are on team-1; carol is on team-2
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

  defp post_member(store, team_id, user_id, token) do
    body = Jason.encode!(%{"user_id" => user_id})

    :post
    |> conn("/api/teams/#{team_id}/members", body)
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("content-type", "application/json")
    |> put_private(:team_store, store)
    |> TeamRouter.call(TeamRouter.init(store: store))
  end

  defp json_body(conn) do
    Jason.decode!(conn.resp_body)
  end

  # -------------------------------------------------------
  # GET /api/teams/:team_id/members — Happy path
  # -------------------------------------------------------

  test "GET returns 200 with members for authorized user", %{store: store} do
    conn = get_members(store, "team-1", "token-alice")

    assert conn.status == 200
    body = json_body(conn)
    assert is_list(body["members"])
    assert "alice" in body["members"]
    assert "bob" in body["members"]
    refute "carol" in body["members"]
  end

  test "GET returns 200 for any member of the team", %{store: store} do
    conn = get_members(store, "team-1", "token-bob")
    assert conn.status == 200
    assert "alice" in json_body(conn)["members"]
  end

  # -------------------------------------------------------
  # GET — Authorization errors
  # -------------------------------------------------------

  test "GET returns 403 when user is not a team member", %{store: store} do
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
    assert json_body(conn)["error"] == "unauthorized"
  end

  # -------------------------------------------------------
  # GET — Not found
  # -------------------------------------------------------

  test "GET returns 404 for non-existent team", %{store: store} do
    conn = get_members(store, "no-such-team", "token-alice")
    assert conn.status == 404
    assert json_body(conn)["error"] == "not_found"
  end

  # -------------------------------------------------------
  # POST /api/teams/:team_id/members — Happy path
  # -------------------------------------------------------

  test "POST returns 201 when adding a new member", %{store: store} do
    conn = post_member(store, "team-1", "carol", "token-alice")

    assert conn.status == 201
    body = json_body(conn)
    assert body["added"] == "carol"

    # Verify carol is now actually in team-1
    assert TeamStore.is_member?(store, "team-1", "carol")
  end

  test "POST newly added member appears in subsequent GET", %{store: store} do
    post_member(store, "team-1", "carol", "token-alice")

    conn = get_members(store, "team-1", "token-alice")
    assert "carol" in json_body(conn)["members"]
  end

  # -------------------------------------------------------
  # POST — Conflict (duplicate member)
  # -------------------------------------------------------

  test "POST returns 409 when member already exists", %{store: store} do
    conn = post_member(store, "team-1", "bob", "token-alice")

    assert conn.status == 409
    assert json_body(conn)["error"] == "conflict"
  end

  # -------------------------------------------------------
  # POST — Authorization errors
  # -------------------------------------------------------

  test "POST returns 403 when user is not a team member", %{store: store} do
    conn = post_member(store, "team-1", "carol", "token-carol")

    assert conn.status == 403
    assert json_body(conn)["error"] == "forbidden"
  end

  test "POST returns 401 with invalid token", %{store: store} do
    body = Jason.encode!(%{"user_id" => "carol"})

    conn =
      :post
      |> conn("/api/teams/team-1/members", body)
      |> put_req_header("authorization", "Bearer token-nobody")
      |> put_req_header("content-type", "application/json")
      |> put_private(:team_store, store)
      |> TeamRouter.call(TeamRouter.init(store: store))

    assert conn.status == 401
    assert json_body(conn)["error"] == "unauthorized"
  end

  # -------------------------------------------------------
  # POST — Not found
  # -------------------------------------------------------

  test "POST returns 404 for non-existent team", %{store: store} do
    conn = post_member(store, "no-such-team", "alice", "token-alice")

    assert conn.status == 404
    assert json_body(conn)["error"] == "not_found"
  end

  # -------------------------------------------------------
  # Key independence / isolation
  # -------------------------------------------------------

  test "operations on team-1 do not affect team-2", %{store: store} do
    # Exhaust interactions with team-1
    post_member(store, "team-1", "carol", "token-alice")

    # team-2 is unaffected — carol is still the only member
    conn = get_members(store, "team-2", "token-carol")
    assert conn.status == 200
    members = json_body(conn)["members"]
    assert members == ["carol"]
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "POST with malformed or missing user_id in body returns 400 or 422", %{store: store} do
    body = Jason.encode!(%{"wrong_field" => "carol"})

    conn =
      :post
      |> conn("/api/teams/team-1/members", body)
      |> put_req_header("authorization", "Bearer token-alice")
      |> put_req_header("content-type", "application/json")
      |> put_private(:team_store, store)
      |> TeamRouter.call(TeamRouter.init(store: store))

    assert conn.status in [400, 422]
  end

  test "response content-type is application/json", %{store: store} do
    conn = get_members(store, "team-1", "token-alice")

    content_type =
      conn
      |> get_resp_header("content-type")
      |> List.first("")

    assert content_type =~ "application/json"
  end

  test "GET returns 404 before 403 when team doesn't exist and user is anyone", %{store: store} do
    # Even for a valid user, a non-existent team is 404, not 403
    conn = get_members(store, "ghost-team", "token-alice")
    assert conn.status == 404
  end

  test "POST returns 404 before 409 when team doesn't exist", %{store: store} do
    conn = post_member(store, "ghost-team", "bob", "token-alice")
    assert conn.status == 404
  end

  # -------------------------------------------------------
  # TeamStore direct API verification
  # -------------------------------------------------------

  test "TeamStore.list_members returns error for unknown team", %{store: store} do
    assert {:error, :not_found} = TeamStore.list_members(store, "nope")
  end

  test "TeamStore.team_exists? returns false for unknown team", %{store: store} do
    refute TeamStore.team_exists?(store, "nope")
  end

  test "TeamStore.is_member? returns false for non-member", %{store: store} do
    refute TeamStore.is_member?(store, "team-1", "carol")
  end

  test "TeamStore.add_member_safe returns conflict for duplicate", %{store: store} do
    assert {:error, :conflict} = TeamStore.add_member_safe(store, "team-1", "alice")
  end

  test "TeamStore.add_member_safe returns not_found for missing team", %{store: store} do
    assert {:error, :not_found} = TeamStore.add_member_safe(store, "nope", "alice")
  end

  test "TeamStore.get_user_by_token returns error for unknown token", %{store: store} do
    assert :error = TeamStore.get_user_by_token(store, "bogus")
  end
end
