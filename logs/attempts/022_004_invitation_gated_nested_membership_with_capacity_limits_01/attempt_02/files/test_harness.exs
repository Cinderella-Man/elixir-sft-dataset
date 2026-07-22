defmodule TeamRouterInvitationTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  setup do
    store = start_supervised!({TeamStore, name: :"store_#{System.unique_integer([:positive])}"})

    :ok = TeamStore.create_user(store, "alice", "token-alice")
    :ok = TeamStore.create_user(store, "bob", "token-bob")
    :ok = TeamStore.create_user(store, "carol", "token-carol")
    :ok = TeamStore.create_user(store, "dave", "token-dave")

    :ok = TeamStore.create_team(store, "team-1", 5)
    :ok = TeamStore.create_team(store, "team-2", 5)
    :ok = TeamStore.create_team(store, "team-full", 2)

    :ok = TeamStore.add_member(store, "team-1", "alice")
    :ok = TeamStore.add_member(store, "team-1", "bob")
    :ok = TeamStore.add_member(store, "team-2", "carol")
    :ok = TeamStore.add_member(store, "team-full", "alice")
    :ok = TeamStore.add_member(store, "team-full", "bob")

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

  defp get_invitations(store, team_id, token) do
    :get
    |> conn("/api/teams/#{team_id}/invitations")
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_private(:team_store, store)
    |> TeamRouter.call(TeamRouter.init(store: store))
  end

  defp post_invite(store, team_id, user_id, token) do
    body = Jason.encode!(%{"user_id" => user_id})

    :post
    |> conn("/api/teams/#{team_id}/invitations", body)
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("content-type", "application/json")
    |> put_private(:team_store, store)
    |> TeamRouter.call(TeamRouter.init(store: store))
  end

  defp post_accept(store, team_id, token) do
    :post
    |> conn("/api/teams/#{team_id}/members", "")
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("content-type", "application/json")
    |> put_private(:team_store, store)
    |> TeamRouter.call(TeamRouter.init(store: store))
  end

  defp json_body(conn), do: Jason.decode!(conn.resp_body)

  # -------------------------------------------------------
  # GET members
  # -------------------------------------------------------

  test "GET members returns 200 with active members", %{store: store} do
    conn = get_members(store, "team-1", "token-alice")
    assert conn.status == 200
    body = json_body(conn)
    assert "alice" in body["members"]
    assert "bob" in body["members"]
    refute "carol" in body["members"]
  end

  test "GET members returns 403 for non-member", %{store: store} do
    conn = get_members(store, "team-1", "token-carol")
    assert conn.status == 403
    assert json_body(conn)["error"] == "forbidden"
  end

  test "GET members returns 401 with missing auth", %{store: store} do
    conn =
      :get
      |> conn("/api/teams/team-1/members")
      |> put_private(:team_store, store)
      |> TeamRouter.call(TeamRouter.init(store: store))

    assert conn.status == 401
  end

  test "GET members returns 404 for missing team", %{store: store} do
    conn = get_members(store, "nope", "token-alice")
    assert conn.status == 404
    assert json_body(conn)["error"] == "not_found"
  end

  # -------------------------------------------------------
  # Invitations
  # -------------------------------------------------------

  test "POST invitations returns 201 and invitee appears as pending, not active", %{store: store} do
    conn = post_invite(store, "team-1", "carol", "token-alice")
    assert conn.status == 201
    assert json_body(conn)["invited"] == "carol"

    inv = get_invitations(store, "team-1", "token-alice")
    assert conn.status == 201
    assert "carol" in json_body(inv)["invitations"]

    members = get_members(store, "team-1", "token-alice")
    refute "carol" in json_body(members)["members"]
  end

  test "POST invitations returns 409 already_member", %{store: store} do
    conn = post_invite(store, "team-1", "bob", "token-alice")
    assert conn.status == 409
    assert json_body(conn)["error"] == "already_member"
  end

  test "POST invitations returns 409 already_invited on duplicate invite", %{store: store} do
    assert post_invite(store, "team-1", "carol", "token-alice").status == 201
    conn = post_invite(store, "team-1", "carol", "token-alice")
    assert conn.status == 409
    assert json_body(conn)["error"] == "already_invited"
  end

  test "POST invitations returns 403 when caller is not an active member", %{store: store} do
    conn = post_invite(store, "team-1", "dave", "token-carol")
    assert conn.status == 403
    assert json_body(conn)["error"] == "forbidden"
  end

  test "POST invitations returns 404 for missing team", %{store: store} do
    conn = post_invite(store, "nope", "dave", "token-alice")
    assert conn.status == 404
  end

  test "POST invitations returns 400 for malformed body", %{store: store} do
    body = Jason.encode!(%{"wrong" => "carol"})

    conn =
      :post
      |> conn("/api/teams/team-1/invitations", body)
      |> put_req_header("authorization", "Bearer token-alice")
      |> put_req_header("content-type", "application/json")
      |> put_private(:team_store, store)
      |> TeamRouter.call(TeamRouter.init(store: store))

    assert conn.status == 400
  end

  test "GET invitations returns 403 for non-member", %{store: store} do
    conn = get_invitations(store, "team-1", "token-carol")
    assert conn.status == 403
  end

  # -------------------------------------------------------
  # Accept
  # -------------------------------------------------------

  test "accept promotes an invited user to active membership", %{store: store} do
    assert post_invite(store, "team-1", "carol", "token-alice").status == 201

    conn = post_accept(store, "team-1", "token-carol")
    assert conn.status == 201
    assert json_body(conn)["joined"] == "team-1"

    assert TeamStore.is_member?(store, "team-1", "carol")
    refute TeamStore.has_invitation?(store, "team-1", "carol")

    members = get_members(store, "team-1", "token-carol")
    assert "carol" in json_body(members)["members"]
  end

  test "accept without a pending invitation returns 403", %{store: store} do
    conn = post_accept(store, "team-1", "token-dave")
    assert conn.status == 403
    assert json_body(conn)["error"] == "forbidden"
  end

  test "accept on a full team returns 409 team_full", %{store: store} do
    assert post_invite(store, "team-full", "carol", "token-alice").status == 201

    conn = post_accept(store, "team-full", "token-carol")
    assert conn.status == 409
    assert json_body(conn)["error"] == "team_full"

    refute TeamStore.is_member?(store, "team-full", "carol")
  end

  test "accept on a missing team returns 404", %{store: store} do
    conn = post_accept(store, "nope", "token-carol")
    assert conn.status == 404
  end

  test "accept with invalid token returns 401", %{store: store} do
    conn = post_accept(store, "team-1", "token-nobody")
    assert conn.status == 401
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

  test "invitations on team-1 do not affect team-2", %{store: store} do
    post_invite(store, "team-1", "dave", "token-alice")

    conn = get_members(store, "team-2", "token-carol")
    assert conn.status == 200
    assert json_body(conn)["members"] == ["carol"]

    {:ok, invs} = TeamStore.list_invitations(store, "team-2")
    assert invs == []
  end

  # -------------------------------------------------------
  # TeamStore direct API verification
  # -------------------------------------------------------

  test "TeamStore.list_members returns not_found for unknown team", %{store: store} do
    assert {:error, :not_found} = TeamStore.list_members(store, "nope")
  end

  test "TeamStore.list_invitations returns not_found for unknown team", %{store: store} do
    assert {:error, :not_found} = TeamStore.list_invitations(store, "nope")
  end

  test "TeamStore.invite returns already_member for existing member", %{store: store} do
    assert {:error, :already_member} = TeamStore.invite(store, "team-1", "alice")
  end

  test "TeamStore.invite returns not_found for missing team", %{store: store} do
    assert {:error, :not_found} = TeamStore.invite(store, "nope", "carol")
  end

  test "TeamStore.invite records a pending invitation", %{store: store} do
    assert {:ok, "carol"} = TeamStore.invite(store, "team-1", "carol")
    assert TeamStore.has_invitation?(store, "team-1", "carol")
    refute TeamStore.is_member?(store, "team-1", "carol")
  end

  test "TeamStore.accept returns no_invitation when none pending", %{store: store} do
    assert {:error, :no_invitation} = TeamStore.accept(store, "team-1", "dave")
  end

  test "TeamStore.accept returns not_found for missing team", %{store: store} do
    assert {:error, :not_found} = TeamStore.accept(store, "nope", "carol")
  end

  test "TeamStore.accept returns team_full when at capacity", %{store: store} do
    assert {:ok, "carol"} = TeamStore.invite(store, "team-full", "carol")
    assert {:error, :team_full} = TeamStore.accept(store, "team-full", "carol")
  end

  test "TeamStore.get_user_by_token returns error for unknown token", %{store: store} do
    assert :error = TeamStore.get_user_by_token(store, "bogus")
  end
end
