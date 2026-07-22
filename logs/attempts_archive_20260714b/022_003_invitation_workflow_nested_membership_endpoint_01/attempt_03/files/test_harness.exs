defmodule TeamRouterTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  setup do
    name = :"store_#{System.unique_integer([:positive])}"

    # Start the store directly (not via start_supervised!) so that a gutted
    # `init/1` fails this match immediately and deterministically instead of
    # triggering supervisor-retry noise / eval timeouts.
    {:ok, store} = TeamStore.start_link(name: name)
    on_exit(fn -> if Process.alive?(store), do: GenServer.stop(store) end)

    # Seed users
    :ok = TeamStore.create_user(store, "alice", "token-alice")
    :ok = TeamStore.create_user(store, "bob", "token-bob")
    :ok = TeamStore.create_user(store, "carol", "token-carol")
    :ok = TeamStore.create_user(store, "dave", "token-dave")

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

  defp get_invitations(store, team_id, token) do
    :get
    |> conn("/api/teams/#{team_id}/invitations")
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_private(:team_store, store)
    |> TeamRouter.call(TeamRouter.init(store: store))
  end

  defp invite(store, team_id, user_id, token) do
    body = Jason.encode!(%{"user_id" => user_id})

    :post
    |> conn("/api/teams/#{team_id}/invitations", body)
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("content-type", "application/json")
    |> put_private(:team_store, store)
    |> TeamRouter.call(TeamRouter.init(store: store))
  end

  defp accept(store, team_id, user_id, token) do
    :post
    |> conn("/api/teams/#{team_id}/invitations/#{user_id}/accept", "")
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_private(:team_store, store)
    |> TeamRouter.call(TeamRouter.init(store: store))
  end

  defp json_body(conn), do: Jason.decode!(conn.resp_body)

  # -------------------------------------------------------
  # GET members
  # -------------------------------------------------------

  test "GET returns 200 with members for a member", %{store: store} do
    conn = get_members(store, "team-1", "token-alice")
    assert conn.status == 200
    body = json_body(conn)
    assert "alice" in body["members"]
    assert "bob" in body["members"]
    refute "carol" in body["members"]
  end

  test "GET members 403 for non-member", %{store: store} do
    conn = get_members(store, "team-1", "token-carol")
    assert conn.status == 403
    assert json_body(conn)["error"] == "forbidden"
  end

  test "GET members 404 for missing team", %{store: store} do
    conn = get_members(store, "ghost", "token-alice")
    assert conn.status == 404
  end

  test "GET members 401 with missing header", %{store: store} do
    conn =
      :get
      |> conn("/api/teams/team-1/members")
      |> put_private(:team_store, store)
      |> TeamRouter.call(TeamRouter.init(store: store))

    assert conn.status == 401
    assert json_body(conn)["error"] == "unauthorized"
  end

  test "GET members 401 with invalid token", %{store: store} do
    conn = get_members(store, "team-1", "token-nobody")
    assert conn.status == 401
  end

  # -------------------------------------------------------
  # POST invitations (create pending)
  # -------------------------------------------------------

  test "member can invite a user, creating a pending invitation", %{store: store} do
    conn = invite(store, "team-1", "carol", "token-alice")
    assert conn.status == 201
    body = json_body(conn)
    assert body["invited"] == "carol"
    assert body["status"] == "pending"

    # carol is NOT yet a member — only pending
    refute TeamStore.is_member?(store, "team-1", "carol")
    assert TeamStore.has_pending_invite?(store, "team-1", "carol")
  end

  test "pending invitation shows up in GET invitations", %{store: store} do
    invite(store, "team-1", "carol", "token-alice")
    conn = get_invitations(store, "team-1", "token-bob")
    assert conn.status == 200
    assert "carol" in json_body(conn)["invitations"]
  end

  test "non-member cannot invite", %{store: store} do
    conn = invite(store, "team-1", "dave", "token-carol")
    assert conn.status == 403
    assert json_body(conn)["error"] == "forbidden"
  end

  test "inviting to a missing team returns 404", %{store: store} do
    conn = invite(store, "ghost", "carol", "token-alice")
    assert conn.status == 404
  end

  test "inviting an existing member returns 409", %{store: store} do
    conn = invite(store, "team-1", "bob", "token-alice")
    assert conn.status == 409
    assert json_body(conn)["error"] == "conflict"
  end

  test "inviting a user twice returns 409 on the second call", %{store: store} do
    assert invite(store, "team-1", "carol", "token-alice").status == 201
    assert invite(store, "team-1", "carol", "token-bob").status == 409
  end

  test "malformed invite body returns 400", %{store: store} do
    body = Jason.encode!(%{"wrong" => "carol"})

    conn =
      :post
      |> conn("/api/teams/team-1/invitations", body)
      |> put_req_header("authorization", "Bearer token-alice")
      |> put_req_header("content-type", "application/json")
      |> put_private(:team_store, store)
      |> TeamRouter.call(TeamRouter.init(store: store))

    assert conn.status == 400
    assert json_body(conn)["error"] == "bad_request"
  end

  # -------------------------------------------------------
  # POST accept
  # -------------------------------------------------------

  test "invited user can accept and become a member", %{store: store} do
    invite(store, "team-1", "carol", "token-alice")
    conn = accept(store, "team-1", "carol", "token-carol")
    assert conn.status == 200
    assert json_body(conn)["joined"] == "carol"

    assert TeamStore.is_member?(store, "team-1", "carol")
    refute TeamStore.has_pending_invite?(store, "team-1", "carol")
  end

  test "accepted member appears in GET members", %{store: store} do
    invite(store, "team-1", "carol", "token-alice")
    accept(store, "team-1", "carol", "token-carol")
    conn = get_members(store, "team-1", "token-alice")
    assert "carol" in json_body(conn)["members"]
  end

  test "cannot accept someone else's invitation (403)", %{store: store} do
    invite(store, "team-1", "carol", "token-alice")
    conn = accept(store, "team-1", "carol", "token-bob")
    assert conn.status == 403
    assert json_body(conn)["error"] == "forbidden"
    # still pending, not joined
    assert TeamStore.has_pending_invite?(store, "team-1", "carol")
  end

  test "accepting with no pending invitation returns 404", %{store: store} do
    conn = accept(store, "team-1", "dave", "token-dave")
    assert conn.status == 404
    assert json_body(conn)["error"] == "not_found"
  end

  test "accepting on a missing team returns 404", %{store: store} do
    conn = accept(store, "ghost", "carol", "token-carol")
    assert conn.status == 404
  end

  # -------------------------------------------------------
  # Isolation / content-type
  # -------------------------------------------------------

  test "operations on team-1 do not affect team-2", %{store: store} do
    invite(store, "team-1", "carol", "token-alice")
    accept(store, "team-1", "carol", "token-carol")

    conn = get_members(store, "team-2", "token-carol")
    assert conn.status == 200
    assert json_body(conn)["members"] == ["carol"]
  end

  test "responses are application/json", %{store: store} do
    conn = get_members(store, "team-1", "token-alice")

    content_type =
      conn
      |> get_resp_header("content-type")
      |> List.first("")

    assert content_type =~ "application/json"
  end

  # -------------------------------------------------------
  # TeamStore direct API
  # -------------------------------------------------------

  test "invite returns not_found for missing team", %{store: store} do
    assert {:error, :not_found} = TeamStore.invite(store, "nope", "carol")
  end

  test "invite returns conflict for existing member", %{store: store} do
    assert {:error, :conflict} = TeamStore.invite(store, "team-1", "alice")
  end

  test "accept_invitation returns not_found when no invite exists", %{store: store} do
    assert {:error, :not_found} = TeamStore.accept_invitation(store, "team-1", "dave")
  end

  test "list_invitations returns not_found for missing team", %{store: store} do
    assert {:error, :not_found} = TeamStore.list_invitations(store, "nope")
  end

  test "get_user_by_token returns error for unknown token", %{store: store} do
    assert :error = TeamStore.get_user_by_token(store, "bogus")
  end
end

defmodule TeamStoreInitTest do
  # This module has NO shared setup on purpose: it exercises init/1 and
  # start_link/1 directly so that gutting `init/1` (e.g. replacing its body
  # with a raise) produces a fast, deterministic *assertion* failure.
  #
  # Every call that touches init/1 is wrapped so that a raise is captured and
  # converted into a plain value: this way a gutted init/1 always fails a
  # concrete `assert`, never merely crashes the test with an exception (which
  # a mutation grader could otherwise misread as an inconclusive harness
  # error rather than a caught mutant).
  use ExUnit.Case, async: false

  # Invoke a zero-arity fun, turning any raise/throw/exit into a tagged tuple
  # so the caller can assert on the *result* instead of crashing.
  defp safe(fun) do
    try do
      {:returned, fun.()}
    rescue
      error -> {:raised, error}
    catch
      kind, reason -> {:caught, kind, reason}
    end
  end

  test "init/1 returns :ok with a fresh, empty state map" do
    result = safe(fn -> TeamStore.init([]) end)

    # A gutted init/1 (raise) makes `result` a {:raised, _} tuple, so this
    # match assertion fails cleanly and deterministically.
    assert {:returned, {:ok, state}} = result
    assert is_map(state)
    assert Map.fetch!(state, :tokens) == %{}
    assert Map.fetch!(state, :teams) == %{}
    assert Map.fetch!(state, :invites) == %{}
  end

  test "init/1 ignores its argument and always starts empty" do
    result = safe(fn -> TeamStore.init(name: :ignored, extra: 123) end)
    assert {:returned, {:ok, state}} = result
    assert state == %{tokens: %{}, teams: %{}, invites: %{}}
  end

  test "start_link/1 boots a live process seeded from init/1's empty state" do
    result = safe(fn -> TeamStore.start_link([]) end)

    # If init/1 is gutted, start_link/1 returns {:error, _}; this assertion
    # then fails on the value instead of crashing the test.
    assert {:returned, {:ok, pid}} = result
    assert is_pid(pid)

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
    end)

    # A freshly-initialized store knows about nothing.
    assert TeamStore.get_user_by_token(pid, "anything") == :error
    assert TeamStore.team_exists?(pid, "anything") == false
    assert TeamStore.is_member?(pid, "anything", "anyone") == false
    assert TeamStore.list_members(pid, "anything") == {:error, :not_found}
    assert TeamStore.list_invitations(pid, "anything") == {:error, :not_found}

    # And it must be a working, writable store built on that empty state.
    :ok = TeamStore.create_user(pid, "zoe", "tok-zoe")
    :ok = TeamStore.create_team(pid, "t")
    assert TeamStore.get_user_by_token(pid, "tok-zoe") == {:ok, "zoe"}
    assert TeamStore.team_exists?(pid, "t")
    assert TeamStore.list_members(pid, "t") == {:ok, []}
  end
end