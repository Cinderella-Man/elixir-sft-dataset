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
    :ok = TeamStore.create_user(store, "dave", "token-dave")

    # Seed teams: team-1 has alice, bob, carol; team-2 has dave
    :ok = TeamStore.create_team(store, "team-1")
    :ok = TeamStore.create_team(store, "team-2")
    :ok = TeamStore.add_member(store, "team-1", "alice")
    :ok = TeamStore.add_member(store, "team-1", "bob")
    :ok = TeamStore.add_member(store, "team-1", "carol")
    :ok = TeamStore.add_member(store, "team-2", "dave")

    # Projects under team-1: proj-a (alice, bob), proj-b (alice)
    :ok = TeamStore.create_project(store, "team-1", "proj-a")
    :ok = TeamStore.create_project(store, "team-1", "proj-b")
    :ok = TeamStore.add_project_member(store, "team-1", "proj-a", "alice")
    :ok = TeamStore.add_project_member(store, "team-1", "proj-a", "bob")
    :ok = TeamStore.add_project_member(store, "team-1", "proj-b", "alice")

    %{store: store}
  end

  # -------------------------------------------------------
  # Helpers
  # -------------------------------------------------------

  defp get_project_members(store, team_id, project_id, token) do
    :get
    |> conn("/api/teams/#{team_id}/projects/#{project_id}/members")
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_private(:team_store, store)
    |> TeamRouter.call(TeamRouter.init(store: store))
  end

  defp get_projects(store, team_id, token) do
    :get
    |> conn("/api/teams/#{team_id}/projects")
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_private(:team_store, store)
    |> TeamRouter.call(TeamRouter.init(store: store))
  end

  defp post_project_member(store, team_id, project_id, user_id, token) do
    body = Jason.encode!(%{"user_id" => user_id})

    :post
    |> conn("/api/teams/#{team_id}/projects/#{project_id}/members", body)
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("content-type", "application/json")
    |> put_private(:team_store, store)
    |> TeamRouter.call(TeamRouter.init(store: store))
  end

  defp json_body(conn), do: Jason.decode!(conn.resp_body)

  # -------------------------------------------------------
  # GET project members — happy path
  # -------------------------------------------------------

  test "GET returns 200 with project members for a project member", %{store: store} do
    conn = get_project_members(store, "team-1", "proj-a", "token-alice")
    assert conn.status == 200
    members = json_body(conn)["members"]
    assert "alice" in members
    assert "bob" in members
    refute "carol" in members
  end

  test "GET works for any project member", %{store: store} do
    conn = get_project_members(store, "team-1", "proj-a", "token-bob")
    assert conn.status == 200
  end

  # -------------------------------------------------------
  # GET — cascading authorization
  # -------------------------------------------------------

  test "team member who is not a project member gets 403", %{store: store} do
    # carol is on team-1 but not on proj-a
    conn = get_project_members(store, "team-1", "proj-a", "token-carol")
    assert conn.status == 403
    assert json_body(conn)["error"] == "forbidden"
  end

  test "non-team-member gets 403", %{store: store} do
    # dave is on team-2, not team-1
    conn = get_project_members(store, "team-1", "proj-a", "token-dave")
    assert conn.status == 403
  end

  test "GET returns 404 for a missing team", %{store: store} do
    conn = get_project_members(store, "ghost", "proj-a", "token-alice")
    assert conn.status == 404
  end

  test "GET returns 404 for a missing project", %{store: store} do
    conn = get_project_members(store, "team-1", "proj-x", "token-alice")
    assert conn.status == 404
  end

  test "GET 404 (missing team) takes precedence over 403", %{store: store} do
    conn = get_project_members(store, "ghost", "proj-a", "token-dave")
    assert conn.status == 404
  end

  # -------------------------------------------------------
  # Auth
  # -------------------------------------------------------

  test "GET 401 with missing header", %{store: store} do
    conn =
      :get
      |> conn("/api/teams/team-1/projects/proj-a/members")
      |> put_private(:team_store, store)
      |> TeamRouter.call(TeamRouter.init(store: store))

    assert conn.status == 401
    assert json_body(conn)["error"] == "unauthorized"
  end

  test "GET 401 with invalid token", %{store: store} do
    conn = get_project_members(store, "team-1", "proj-a", "token-nobody")
    assert conn.status == 401
  end

  # -------------------------------------------------------
  # GET projects list
  # -------------------------------------------------------

  test "team member lists projects", %{store: store} do
    conn = get_projects(store, "team-1", "token-carol")
    assert conn.status == 200
    projects = json_body(conn)["projects"]
    assert "proj-a" in projects
    assert "proj-b" in projects
  end

  test "non-team-member cannot list projects", %{store: store} do
    conn = get_projects(store, "team-1", "token-dave")
    assert conn.status == 403
  end

  test "listing projects for a missing team returns 404", %{store: store} do
    conn = get_projects(store, "ghost", "token-alice")
    assert conn.status == 404
  end

  # -------------------------------------------------------
  # POST — happy path
  # -------------------------------------------------------

  test "project member adds a team member to the project (201)", %{store: store} do
    # carol is on team-1; alice (project member) adds her to proj-a
    conn = post_project_member(store, "team-1", "proj-a", "carol", "token-alice")
    assert conn.status == 201
    assert json_body(conn)["added"] == "carol"
    assert TeamStore.is_project_member?(store, "team-1", "proj-a", "carol")
  end

  test "newly added project member appears in GET", %{store: store} do
    post_project_member(store, "team-1", "proj-a", "carol", "token-alice")
    conn = get_project_members(store, "team-1", "proj-a", "token-alice")
    assert "carol" in json_body(conn)["members"]
  end

  # -------------------------------------------------------
  # POST — cross-resource constraint (422)
  # -------------------------------------------------------

  test "adding a non-team-member to a project returns 422", %{store: store} do
    # dave is not a member of team-1 at all
    conn = post_project_member(store, "team-1", "proj-a", "dave", "token-alice")
    assert conn.status == 422
    assert json_body(conn)["error"] == "not_a_team_member"
    refute TeamStore.is_project_member?(store, "team-1", "proj-a", "dave")
  end

  # -------------------------------------------------------
  # POST — conflict
  # -------------------------------------------------------

  test "adding an existing project member returns 409", %{store: store} do
    conn = post_project_member(store, "team-1", "proj-a", "bob", "token-alice")
    assert conn.status == 409
    assert json_body(conn)["error"] == "conflict"
  end

  # -------------------------------------------------------
  # POST — authorization cascade for the actor
  # -------------------------------------------------------

  test "team member who is not a project member cannot add (403)", %{store: store} do
    # carol is on team-1 but not proj-a
    conn = post_project_member(store, "team-1", "proj-a", "bob", "token-carol")
    assert conn.status == 403
  end

  test "POST returns 404 for a missing project", %{store: store} do
    conn = post_project_member(store, "team-1", "proj-x", "carol", "token-alice")
    assert conn.status == 404
  end

  test "POST returns 404 for a missing team", %{store: store} do
    conn = post_project_member(store, "ghost", "proj-a", "carol", "token-alice")
    assert conn.status == 404
  end

  test "POST with malformed body returns 400", %{store: store} do
    body = Jason.encode!(%{"wrong" => "carol"})

    conn =
      :post
      |> conn("/api/teams/team-1/projects/proj-a/members", body)
      |> put_req_header("authorization", "Bearer token-alice")
      |> put_req_header("content-type", "application/json")
      |> put_private(:team_store, store)
      |> TeamRouter.call(TeamRouter.init(store: store))

    assert conn.status == 400
    assert json_body(conn)["error"] == "bad_request"
  end

  # -------------------------------------------------------
  # Isolation / content-type
  # -------------------------------------------------------

  test "adding to proj-a does not affect proj-b", %{store: store} do
    post_project_member(store, "team-1", "proj-a", "carol", "token-alice")
    conn = get_project_members(store, "team-1", "proj-b", "token-alice")
    assert json_body(conn)["members"] == ["alice"]
  end

  test "responses are application/json", %{store: store} do
    conn = get_project_members(store, "team-1", "proj-a", "token-alice")

    content_type =
      conn
      |> get_resp_header("content-type")
      |> List.first("")

    assert content_type =~ "application/json"
  end

  # -------------------------------------------------------
  # TeamStore direct API
  # -------------------------------------------------------

  test "add_project_member_safe returns not_found for missing project", %{store: store} do
    assert {:error, :not_found} = TeamStore.add_project_member_safe(store, "team-1", "nope", "alice")
  end

  test "add_project_member_safe returns not_team_member", %{store: store} do
    assert {:error, :not_team_member} =
             TeamStore.add_project_member_safe(store, "team-1", "proj-a", "dave")
  end

  test "add_project_member_safe returns conflict for duplicate", %{store: store} do
    assert {:error, :conflict} =
             TeamStore.add_project_member_safe(store, "team-1", "proj-a", "alice")
  end

  test "list_project_members returns not_found for unknown project", %{store: store} do
    assert {:error, :not_found} = TeamStore.list_project_members(store, "team-1", "nope")
  end

  test "list_projects returns not_found for unknown team", %{store: store} do
    assert {:error, :not_found} = TeamStore.list_projects(store, "nope")
  end

  test "project_exists? is false for unknown project", %{store: store} do
    refute TeamStore.project_exists?(store, "team-1", "nope")
  end

  test "get_user_by_token returns error for unknown token", %{store: store} do
    assert :error = TeamStore.get_user_by_token(store, "bogus")
  end
end

defmodule TeamStoreInitTest do
  use ExUnit.Case, async: false

  # These tests exercise `TeamStore.init/1` directly (and via a freshly started
  # store) without the shared router setup, so they stand on their own.
  #
  # `init/1` has a single job: build and return `{:ok, empty_state}`. The direct
  # assertions below call the callback as a plain function, so if it is gutted
  # (for example replaced with `raise`), each assertion fails immediately and
  # conclusively — no GenServer start-up, no crash reports, no fragile
  # `try/after` teardown that could turn the failure into an inconclusive error.

  @empty_state %{tokens: %{}, teams: %{}, projects: %{}}

  test "init/1 returns exactly the empty in-memory state map" do
    assert TeamStore.init([]) == {:ok, @empty_state}
  end

  test "init/1 ignores its options and always starts empty" do
    assert {:ok, state} = TeamStore.init(name: :whatever, extra: :ignored)
    assert state == @empty_state
    assert Enum.sort(Map.keys(state)) == [:projects, :teams, :tokens]
  end

  test "init/1 seeds the three collections as distinct empty maps" do
    assert {:ok, %{tokens: tokens, teams: teams, projects: projects}} = TeamStore.init([])
    assert tokens == %{}
    assert teams == %{}
    assert projects == %{}
  end

  test "a freshly started store begins with no users, teams or projects" do
    store = start_supervised!({TeamStore, []})

    assert :error = TeamStore.get_user_by_token(store, "anything")
    refute TeamStore.team_exists?(store, "team-1")
    refute TeamStore.is_member?(store, "team-1", "alice")
    refute TeamStore.project_exists?(store, "team-1", "proj-a")
    assert {:error, :not_found} = TeamStore.list_projects(store, "team-1")

    # And the empty state built by init/1 is genuinely usable once seeded.
    :ok = TeamStore.create_user(store, "alice", "tok-alice")
    assert {:ok, "alice"} = TeamStore.get_user_by_token(store, "tok-alice")

    :ok = TeamStore.create_team(store, "team-1")
    assert TeamStore.team_exists?(store, "team-1")
    assert {:ok, []} = TeamStore.list_projects(store, "team-1")
  end
end