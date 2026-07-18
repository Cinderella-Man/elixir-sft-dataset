# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule TeamStore do
  @moduledoc """
  In-memory `GenServer` holding users, teams and memberships.
  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  def create_user(server, id, token), do: GenServer.call(server, {:create_user, id, token})

  @doc "Creates a team `team_id`. Returns `:ok` or `{:error, reason}`."
  def create_team(server, team_id), do: GenServer.call(server, {:create_team, team_id})

  def add_member(server, team_id, user_id),
    do: GenServer.call(server, {:add_member, team_id, user_id})

  def get_user_by_token(server, token), do: GenServer.call(server, {:get_user_by_token, token})

  def team_exists?(server, team_id), do: GenServer.call(server, {:team_exists?, team_id})

  def is_member?(server, team_id, user_id),
    do: GenServer.call(server, {:is_member?, team_id, user_id})

  def list_members(server, team_id), do: GenServer.call(server, {:list_members, team_id})

  def add_member_safe(server, team_id, user_id),
    do: GenServer.call(server, {:add_member_safe, team_id, user_id})

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    {:ok, %{tokens: %{}, teams: %{}}}
  end

  @impl true
  def handle_call({:create_user, id, token}, _from, state) do
    {:reply, :ok, put_in(state.tokens[token], id)}
  end

  def handle_call({:create_team, team_id}, _from, state) do
    teams = Map.put_new(state.teams, team_id, [])
    {:reply, :ok, %{state | teams: teams}}
  end

  def handle_call({:add_member, team_id, user_id}, _from, state) do
    members = Map.get(state.teams, team_id, [])
    members = if user_id in members, do: members, else: members ++ [user_id]
    {:reply, :ok, %{state | teams: Map.put(state.teams, team_id, members)}}
  end

  def handle_call({:get_user_by_token, token}, _from, state) do
    case Map.fetch(state.tokens, token) do
      {:ok, user_id} -> {:reply, {:ok, user_id}, state}
      :error -> {:reply, :error, state}
    end
  end

  def handle_call({:team_exists?, team_id}, _from, state) do
    {:reply, Map.has_key?(state.teams, team_id), state}
  end

  def handle_call({:is_member?, team_id, user_id}, _from, state) do
    {:reply, user_id in Map.get(state.teams, team_id, []), state}
  end

  def handle_call({:list_members, team_id}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      {:ok, members} -> {:reply, {:ok, members}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:add_member_safe, team_id, user_id}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, members} ->
        if user_id in members do
          {:reply, {:error, :conflict}, state}
        else
          teams = Map.put(state.teams, team_id, members ++ [user_id])
          {:reply, {:ok, user_id}, %{state | teams: teams}}
        end
    end
  end
end

defmodule AuthPlug do
  @moduledoc """
  Plug that authenticates a bearer token via `TeamStore` and assigns
  `:current_user`, or halts with a 401 JSON response.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, opts) do
    store = resolve_store(conn, opts)

    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        case TeamStore.get_user_by_token(store, token) do
          {:ok, user_id} -> assign(conn, :current_user, user_id)
          :error -> unauthorized(conn)
        end

      _ ->
        unauthorized(conn)
    end
  end

  defp resolve_store(conn, opts) do
    conn.private[:team_store] || Keyword.get(opts, :store) ||
      Keyword.get(conn.assigns[:router_opts] || [], :store)
  end

  defp unauthorized(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, Jason.encode!(%{error: "unauthorized"}))
    |> halt()
  end
end

defmodule TeamRouter do
  @moduledoc """
  `Plug.Router` exposing nested team-membership resources, protected by
  `AuthPlug`.
  """

  use Plug.Router, copy_opts_to_assign: :router_opts

  plug(AuthPlug)
  plug(:match)
  plug(:dispatch)

  get "/api/teams/:team_id/members" do
    store = store(conn)
    user = conn.assigns.current_user

    cond do
      not TeamStore.team_exists?(store, team_id) ->
        json(conn, 404, %{error: "not_found"})

      not TeamStore.is_member?(store, team_id, user) ->
        json(conn, 403, %{error: "forbidden"})

      true ->
        {:ok, members} = TeamStore.list_members(store, team_id)
        json(conn, 200, %{members: members})
    end
  end

  post "/api/teams/:team_id/members" do
    store = store(conn)
    user = conn.assigns.current_user

    cond do
      not TeamStore.team_exists?(store, team_id) ->
        json(conn, 404, %{error: "not_found"})

      not TeamStore.is_member?(store, team_id, user) ->
        json(conn, 403, %{error: "forbidden"})

      true ->
        add_member(conn, store, team_id)
    end
  end

  match _ do
    json(conn, 404, %{error: "not_found"})
  end

  defp add_member(conn, store, team_id) do
    case read_user_id(conn) do
      {:ok, new_user_id, conn} ->
        case TeamStore.add_member_safe(store, team_id, new_user_id) do
          {:ok, user_id} -> json(conn, 201, %{added: user_id})
          {:error, :conflict} -> json(conn, 409, %{error: "conflict"})
          {:error, :not_found} -> json(conn, 404, %{error: "not_found"})
        end

      {:error, conn} ->
        json(conn, 400, %{error: "bad_request"})
    end
  end

  defp read_user_id(conn) do
    {:ok, body, conn} = read_body(conn)

    case Jason.decode(body) do
      {:ok, %{"user_id" => user_id}} when is_binary(user_id) -> {:ok, user_id, conn}
      _ -> {:error, conn}
    end
  end

  defp store(conn) do
    conn.private[:team_store] || Keyword.get(conn.assigns[:router_opts] || [], :store)
  end

  defp json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
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
    # TODO
  end

  test "TeamStore.add_member_safe returns not_found for missing team", %{store: store} do
    assert {:error, :not_found} = TeamStore.add_member_safe(store, "nope", "alice")
  end

  test "TeamStore.get_user_by_token returns error for unknown token", %{store: store} do
    assert :error = TeamStore.get_user_by_token(store, "bogus")
  end

  test "AuthPlug resolves the store from its init option alone", %{store: store} do
    conn =
      :get
      |> conn("/api/teams/team-1/members")
      |> put_req_header("authorization", "Bearer token-alice")
      |> AuthPlug.call(AuthPlug.init(store: store))

    refute conn.halted
    assert conn.assigns.current_user == "alice"
  end

  test "TeamRouter resolves the store from its :store option without conn private", %{
    store: store
  } do
    conn =
      :get
      |> conn("/api/teams/team-1/members")
      |> put_req_header("authorization", "Bearer token-alice")
      |> TeamRouter.call(TeamRouter.init(store: store))

    assert conn.status == 200
    assert "alice" in Jason.decode!(conn.resp_body)["members"]
  end

  test "unknown route without credentials is rejected by AuthPlug with 401", %{store: store} do
    conn =
      :get
      |> conn("/api/teams/team-1/nonsense")
      |> TeamRouter.call(TeamRouter.init(store: store))

    assert conn.status == 401
    assert Jason.decode!(conn.resp_body)["error"] == "unauthorized"
    assert conn.halted
  end

  test "authorization header without the Bearer scheme is unauthorized", %{store: store} do
    conn =
      :get
      |> conn("/api/teams/team-1/members")
      |> put_req_header("authorization", "Basic token-alice")
      |> put_private(:team_store, store)
      |> TeamRouter.call(TeamRouter.init(store: store))

    assert conn.status == 401
    assert Jason.decode!(conn.resp_body)["error"] == "unauthorized"
    assert conn.halted
  end

  test "error responses carry the application/json content-type", %{store: store} do
    conns = [
      get_members(store, "no-such-team", "token-alice"),
      get_members(store, "team-1", "token-carol"),
      get_members(store, "team-1", "token-nobody"),
      post_member(store, "team-1", "bob", "token-alice")
    ]

    for conn <- conns do
      content_type = conn |> get_resp_header("content-type") |> List.first("")
      assert content_type =~ "application/json"
    end

    assert Enum.map(conns, & &1.status) == [404, 403, 401, 409]
  end

  test "TeamStore registers under the :name option and serves calls by that name" do
    name = :"named_store_#{System.unique_integer([:positive])}"
    start_supervised!(%{id: name, start: {TeamStore, :start_link, [[name: name]]}})

    assert is_pid(Process.whereis(name))
    assert :ok = TeamStore.create_team(name, "team-x")
    assert :ok = TeamStore.create_user(name, "dave", "token-dave")
    assert :ok = TeamStore.add_member(name, "team-x", "dave")
    assert TeamStore.team_exists?(name, "team-x")
    assert TeamStore.is_member?(name, "team-x", "dave")
    assert {:ok, "dave"} = TeamStore.get_user_by_token(name, "token-dave")
    assert {:ok, ["dave"]} = TeamStore.list_members(name, "team-x")
  end
end
```
