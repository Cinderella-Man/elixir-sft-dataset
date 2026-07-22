defmodule TeamRouterInvitationTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  setup do
    store = start_supervised!({TeamStore, name: :"store_#{System.unique_integer([:positive])}"})

    # Seed users
    :ok = TeamStore.create_user(store, "alice", "token-alice")
    :ok = TeamStore.create_user(store, "bob", "token-bob")
    :ok = TeamStore.create_user(store, "carol", "token-carol")
    :ok = TeamStore.create_user(store, "dave", "token-dave")

    # Seed teams
    :ok = TeamStore.create_team(store, "team-1")
    :ok = TeamStore.create_team(store, "team-2")

    # alice and bob are active members of team-1; carol is on team-2
    :ok = TeamStore.add_member(store, "team-1", "alice")
    :ok = TeamStore.add_member(store, "team-1", "bob")
    :ok = TeamStore.add_member(store, "team-2", "carol")

    %{store: store}
  end

  # -------------------------------------------------------
  # Helpers
  # -------------------------------------------------------

  defp call(conn, store) do
    conn
    |> put_private(:team_store, store)
    |> TeamRouter.call(TeamRouter.init(store: store))
  end

  defp get_members(store, team_id, token) do
    :get
    |> conn("/api/teams/#{team_id}/members")
    |> put_req_header("authorization", "Bearer #{token}")
    |> call(store)
  end

  defp get_invitations(store, team_id, token) do
    :get
    |> conn("/api/teams/#{team_id}/invitations")
    |> put_req_header("authorization", "Bearer #{token}")
    |> call(store)
  end

  defp post_invite(store, team_id, user_id, token) do
    body = Jason.encode!(%{"user_id" => user_id})

    :post
    |> conn("/api/teams/#{team_id}/invitations", body)
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("content-type", "application/json")
    |> call(store)
  end

  defp post_accept(store, team_id, user_id, token) do
    :post
    |> conn("/api/teams/#{team_id}/invitations/#{user_id}/accept", "")
    |> put_req_header("authorization", "Bearer #{token}")
    |> call(store)
  end

  defp post_decline(store, team_id, user_id, token) do
    :post
    |> conn("/api/teams/#{team_id}/invitations/#{user_id}/decline", "")
    |> put_req_header("authorization", "Bearer #{token}")
    |> call(store)
  end

  defp json_body(conn), do: Jason.decode!(conn.resp_body)

  # -------------------------------------------------------
  # GET /members
  # -------------------------------------------------------

  test "GET members returns 200 with active members for a member", %{store: store} do
    conn = get_members(store, "team-1", "token-alice")
    assert conn.status == 200
    body = json_body(conn)
    assert is_list(body["members"])
    assert "alice" in body["members"]
    assert "bob" in body["members"]
    refute "carol" in body["members"]
  end

  test "GET members returns 403 for a non-member", %{store: store} do
    conn = get_members(store, "team-1", "token-carol")
    assert conn.status == 403
    assert json_body(conn)["error"] == "forbidden"
  end

  test "GET members returns 401 with missing auth header", %{store: store} do
    conn =
      :get
      |> conn("/api/teams/team-1/members")
      |> call(store)

    assert conn.status == 401
    assert json_body(conn)["error"] == "unauthorized"
  end

  test "GET members returns 401 with invalid token", %{store: store} do
    conn = get_members(store, "team-1", "token-nobody")
    assert conn.status == 401
    assert json_body(conn)["error"] == "unauthorized"
  end

  test "GET members returns 404 for non-existent team", %{store: store} do
    conn = get_members(store, "ghost-team", "token-alice")
    assert conn.status == 404
    assert json_body(conn)["error"] == "not_found"
  end

  # -------------------------------------------------------
  # GET /invitations
  # -------------------------------------------------------

  test "GET invitations returns 200 with an empty list initially", %{store: store} do
    conn = get_invitations(store, "team-1", "token-alice")
    assert conn.status == 200
    assert json_body(conn)["invitations"] == []
  end

  test "GET invitations returns 403 for a non-member", %{store: store} do
    conn = get_invitations(store, "team-1", "token-carol")
    assert conn.status == 403
    assert json_body(conn)["error"] == "forbidden"
  end

  test "GET invitations returns 404 for a non-existent team", %{store: store} do
    conn = get_invitations(store, "ghost-team", "token-alice")
    assert conn.status == 404
    assert json_body(conn)["error"] == "not_found"
  end

  # -------------------------------------------------------
  # POST /invitations
  # -------------------------------------------------------

  test "POST invitations returns 201 and lists the pending invitation", %{store: store} do
    conn = post_invite(store, "team-1", "dave", "token-alice")
    assert conn.status == 201
    assert json_body(conn)["invited"] == "dave"

    listing = get_invitations(store, "team-1", "token-alice")
    assert "dave" in json_body(listing)["invitations"]
  end

  test "POST invitations does not make the invited user a member yet", %{store: store} do
    post_invite(store, "team-1", "dave", "token-alice")

    refute TeamStore.is_member?(store, "team-1", "dave")

    conn = get_members(store, "team-1", "token-alice")
    refute "dave" in json_body(conn)["members"]
  end

  test "POST invitations returns 409 conflict when inviting an existing member", %{store: store} do
    conn = post_invite(store, "team-1", "bob", "token-alice")
    assert conn.status == 409
    assert json_body(conn)["error"] == "conflict"
  end

  test "POST invitations returns 409 already_invited on a duplicate invite", %{store: store} do
    assert post_invite(store, "team-1", "dave", "token-alice").status == 201

    conn = post_invite(store, "team-1", "dave", "token-bob")
    assert conn.status == 409
    assert json_body(conn)["error"] == "already_invited"
  end

  test "POST invitations returns 403 when inviter is not a member", %{store: store} do
    conn = post_invite(store, "team-1", "dave", "token-carol")
    assert conn.status == 403
    assert json_body(conn)["error"] == "forbidden"
  end

  test "POST invitations returns 404 for a non-existent team", %{store: store} do
    conn = post_invite(store, "ghost-team", "dave", "token-alice")
    assert conn.status == 404
    assert json_body(conn)["error"] == "not_found"
  end

  test "POST invitations returns 401 with an invalid token", %{store: store} do
    body = Jason.encode!(%{"user_id" => "dave"})

    conn =
      :post
      |> conn("/api/teams/team-1/invitations", body)
      |> put_req_header("authorization", "Bearer token-nobody")
      |> put_req_header("content-type", "application/json")
      |> call(store)

    assert conn.status == 401
    assert json_body(conn)["error"] == "unauthorized"
  end

  test "POST invitations returns 400 for a body missing user_id", %{store: store} do
    body = Jason.encode!(%{"wrong_field" => "dave"})

    conn =
      :post
      |> conn("/api/teams/team-1/invitations", body)
      |> put_req_header("authorization", "Bearer token-alice")
      |> put_req_header("content-type", "application/json")
      |> call(store)

    assert conn.status == 400
    assert json_body(conn)["error"] == "bad_request"
  end

  # -------------------------------------------------------
  # POST /accept
  # -------------------------------------------------------

  test "POST accept turns the invitation into an active membership", %{store: store} do
    post_invite(store, "team-1", "dave", "token-alice")

    conn = post_accept(store, "team-1", "dave", "token-dave")
    assert conn.status == 200
    assert json_body(conn)["accepted"] == "dave"

    assert TeamStore.is_member?(store, "team-1", "dave")

    members = get_members(store, "team-1", "token-alice")
    assert "dave" in json_body(members)["members"]
  end

  test "POST accept removes the invitation from the pending list", %{store: store} do
    post_invite(store, "team-1", "dave", "token-alice")
    post_accept(store, "team-1", "dave", "token-dave")

    listing = get_invitations(store, "team-1", "token-alice")
    refute "dave" in json_body(listing)["invitations"]
  end

  test "POST accept returns 403 when accepting someone else's invitation", %{store: store} do
    post_invite(store, "team-1", "dave", "token-alice")

    conn = post_accept(store, "team-1", "dave", "token-bob")
    assert conn.status == 403
    assert json_body(conn)["error"] == "forbidden"
  end

  test "POST accept returns 409 no_invitation when there is no pending invite", %{store: store} do
    conn = post_accept(store, "team-1", "dave", "token-dave")
    assert conn.status == 409
    assert json_body(conn)["error"] == "no_invitation"
  end

  test "POST accept returns 404 for a non-existent team", %{store: store} do
    conn = post_accept(store, "ghost-team", "dave", "token-dave")
    assert conn.status == 404
    assert json_body(conn)["error"] == "not_found"
  end

  # -------------------------------------------------------
  # POST /decline
  # -------------------------------------------------------

  test "POST decline removes the invitation without making a member", %{store: store} do
    post_invite(store, "team-1", "dave", "token-alice")

    conn = post_decline(store, "team-1", "dave", "token-dave")
    assert conn.status == 200
    assert json_body(conn)["declined"] == "dave"

    refute TeamStore.is_member?(store, "team-1", "dave")

    listing = get_invitations(store, "team-1", "token-alice")
    refute "dave" in json_body(listing)["invitations"]
  end

  test "POST decline returns 409 no_invitation when there is no pending invite", %{store: store} do
    conn = post_decline(store, "team-1", "dave", "token-dave")
    assert conn.status == 409
    assert json_body(conn)["error"] == "no_invitation"
  end

  test "POST decline returns 403 when declining someone else's invitation", %{store: store} do
    post_invite(store, "team-1", "dave", "token-alice")

    conn = post_decline(store, "team-1", "dave", "token-bob")
    assert conn.status == 403
    assert json_body(conn)["error"] == "forbidden"
  end

  # -------------------------------------------------------
  # Cross-cutting
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

    listing = get_invitations(store, "team-2", "token-carol")
    assert json_body(listing)["invitations"] == []
  end

  # -------------------------------------------------------
  # TeamStore direct API verification
  # -------------------------------------------------------

  test "TeamStore.invite_member returns conflict for an existing member", %{store: store} do
    assert {:error, :conflict} = TeamStore.invite_member(store, "team-1", "alice")
  end

  test "TeamStore.invite_member returns already_invited on duplicate", %{store: store} do
    assert {:ok, "dave"} = TeamStore.invite_member(store, "team-1", "dave")
    assert {:error, :already_invited} = TeamStore.invite_member(store, "team-1", "dave")
  end

  test "TeamStore.invite_member returns not_found for a missing team", %{store: store} do
    assert {:error, :not_found} = TeamStore.invite_member(store, "nope", "dave")
  end

  test "TeamStore.is_invited? reflects a pending invitation", %{store: store} do
    refute TeamStore.is_invited?(store, "team-1", "dave")
    assert {:ok, "dave"} = TeamStore.invite_member(store, "team-1", "dave")
    assert TeamStore.is_invited?(store, "team-1", "dave")
  end

  test "TeamStore.accept_invite adds member and clears invitation", %{store: store} do
    assert {:ok, "dave"} = TeamStore.invite_member(store, "team-1", "dave")
    assert {:ok, "dave"} = TeamStore.accept_invite(store, "team-1", "dave")
    assert TeamStore.is_member?(store, "team-1", "dave")
    refute TeamStore.is_invited?(store, "team-1", "dave")
  end

  test "TeamStore.accept_invite returns no_invitation without a pending invite", %{store: store} do
    assert {:error, :no_invitation} = TeamStore.accept_invite(store, "team-1", "dave")
  end

  test "TeamStore.decline_invite clears invitation without adding member", %{store: store} do
    assert {:ok, "dave"} = TeamStore.invite_member(store, "team-1", "dave")
    assert {:ok, "dave"} = TeamStore.decline_invite(store, "team-1", "dave")
    refute TeamStore.is_member?(store, "team-1", "dave")
    refute TeamStore.is_invited?(store, "team-1", "dave")
  end

  test "TeamStore.list_invitations returns not_found for a missing team", %{store: store} do
    assert {:error, :not_found} = TeamStore.list_invitations(store, "nope")
  end

  test "TeamStore.list_members returns not_found for a missing team", %{store: store} do
    assert {:error, :not_found} = TeamStore.list_members(store, "nope")
  end

  test "TeamStore.get_user_by_token returns error for unknown token", %{store: store} do
    assert :error = TeamStore.get_user_by_token(store, "bogus")
  end
end
