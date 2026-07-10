# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule TeamStore do
  @moduledoc """
  In-memory state store for users, teams, memberships, and per-team version
  numbers, implemented as a `GenServer`.

  Every team tracks a monotonically increasing version. Membership mutations
  bump the version, which enables optimistic concurrency control: a client that
  presents a stale version when writing is rejected so that lost updates can be
  detected.
  """

  use GenServer

  @typedoc "Opaque server reference — a pid or registered name."
  @type server :: GenServer.server()

  @typedoc "Internal server state."
  @type state :: %{
          users: %{optional(String.t()) => String.t()},
          tokens: %{optional(String.t()) => String.t()},
          teams: %{optional(String.t()) => %{members: [String.t()], version: non_neg_integer()}}
        }

  # -- Client API ------------------------------------------------------------

  @doc """
  Starts the store process.

  Accepts a `:name` option used to register the process.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, rest} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, rest, gen_opts)
  end

  @doc """
  Stores a user with the given `id` and bearer `token`.
  """
  @spec create_user(server(), String.t(), String.t()) :: :ok
  def create_user(server, id, token) do
    GenServer.call(server, {:create_user, id, token})
  end

  @doc """
  Creates a team with an empty member list and version `0`.
  """
  @spec create_team(server(), String.t()) :: :ok
  def create_team(server, team_id) do
    GenServer.call(server, {:create_team, team_id})
  end

  @doc """
  Adds a user to a team directly (for seeding).

  Adding a not-yet-present user increments the team's version by 1; adding a
  user already present is a no-op that leaves the version unchanged.
  """
  @spec add_member(server(), String.t(), String.t()) :: :ok
  def add_member(server, team_id, user_id) do
    GenServer.call(server, {:add_member, team_id, user_id})
  end

  @doc """
  Looks up a user id by bearer token.

  Returns `{:ok, user_id}` or `:error`.
  """
  @spec get_user_by_token(server(), String.t()) :: {:ok, String.t()} | :error
  def get_user_by_token(server, token) do
    GenServer.call(server, {:get_user_by_token, token})
  end

  @doc """
  Returns whether a team exists.
  """
  @spec team_exists?(server(), String.t()) :: boolean()
  def team_exists?(server, team_id) do
    GenServer.call(server, {:team_exists?, team_id})
  end

  @doc """
  Returns whether `user_id` is a member of `team_id`.
  """
  @spec is_member?(server(), String.t(), String.t()) :: boolean()
  def is_member?(server, team_id, user_id) do
    GenServer.call(server, {:is_member?, team_id, user_id})
  end

  @doc """
  Returns `{:ok, version}` for the team, or `{:error, :not_found}`.
  """
  @spec get_version(server(), String.t()) :: {:ok, non_neg_integer()} | {:error, :not_found}
  def get_version(server, team_id) do
    GenServer.call(server, {:get_version, team_id})
  end

  @doc """
  Returns `{:ok, list_of_user_ids}` for the team, or `{:error, :not_found}`.
  """
  @spec list_members(server(), String.t()) :: {:ok, [String.t()]} | {:error, :not_found}
  def list_members(server, team_id) do
    GenServer.call(server, {:list_members, team_id})
  end

  @doc """
  Atomically adds a member only if all preconditions hold, in this order:

    1. team must exist, else `{:error, :not_found}`;
    2. `expected_version` must equal the current version, else `{:error, :stale}`;
    3. the user must not already be a member, else `{:error, :conflict}`;
    4. otherwise append the user, bump the version, and return
       `{:ok, user_id, new_version}`.
  """
  @spec add_member_safe(server(), String.t(), String.t(), integer()) ::
          {:ok, String.t(), non_neg_integer()}
          | {:error, :not_found | :stale | :conflict}
  def add_member_safe(server, team_id, user_id, expected_version) do
    GenServer.call(server, {:add_member_safe, team_id, user_id, expected_version})
  end

  # -- Server callbacks ------------------------------------------------------

  @impl true
  @spec init(keyword()) :: {:ok, state()}
  def init(_opts) do
    {:ok, %{users: %{}, tokens: %{}, teams: %{}}}
  end

  @impl true
  def handle_call({:create_user, id, token}, _from, state) do
    state = %{
      state
      | users: Map.put(state.users, id, token),
        tokens: Map.put(state.tokens, token, id)
    }

    {:reply, :ok, state}
  end

  def handle_call({:create_team, team_id}, _from, state) do
    teams = Map.put_new(state.teams, team_id, %{members: [], version: 0})
    {:reply, :ok, %{state | teams: teams}}
  end

  def handle_call({:add_member, team_id, user_id}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      {:ok, %{members: members, version: version} = team} ->
        if user_id in members do
          {:reply, :ok, state}
        else
          team = %{team | members: members ++ [user_id], version: version + 1}
          {:reply, :ok, %{state | teams: Map.put(state.teams, team_id, team)}}
        end

      :error ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:get_user_by_token, token}, _from, state) do
    {:reply, Map.fetch(state.tokens, token), state}
  end

  def handle_call({:team_exists?, team_id}, _from, state) do
    {:reply, Map.has_key?(state.teams, team_id), state}
  end

  def handle_call({:is_member?, team_id, user_id}, _from, state) do
    member? =
      case Map.fetch(state.teams, team_id) do
        {:ok, %{members: members}} -> user_id in members
        :error -> false
      end

    {:reply, member?, state}
  end

  def handle_call({:get_version, team_id}, _from, state) do
    reply =
      case Map.fetch(state.teams, team_id) do
        {:ok, %{version: version}} -> {:ok, version}
        :error -> {:error, :not_found}
      end

    {:reply, reply, state}
  end

  def handle_call({:list_members, team_id}, _from, state) do
    reply =
      case Map.fetch(state.teams, team_id) do
        {:ok, %{members: members}} -> {:ok, members}
        :error -> {:error, :not_found}
      end

    {:reply, reply, state}
  end

  def handle_call({:add_member_safe, team_id, user_id, expected_version}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, %{version: version}} when version != expected_version ->
        {:reply, {:error, :stale}, state}

      {:ok, %{members: members, version: version} = team} ->
        if user_id in members do
          {:reply, {:error, :conflict}, state}
        else
          new_version = version + 1
          team = %{team | members: members ++ [user_id], version: new_version}
          state = %{state | teams: Map.put(state.teams, team_id, team)}
          {:reply, {:ok, user_id, new_version}, state}
        end
    end
  end
end

defmodule AuthPlug do
  @moduledoc """
  A `Plug` that authenticates requests via a bearer token.

  It reads the `authorization` header, expects the form `Bearer <token>`, and
  resolves the token through `TeamStore.get_user_by_token/2`. On success it
  assigns `:current_user` to the connection; otherwise it halts with a 401 JSON
  response.

  Requires a `:store` option at init time identifying the `TeamStore` process.
  """

  @behaviour Plug

  import Plug.Conn

  @doc """
  Initializes the plug, requiring a `:store` option.
  """
  @spec init(keyword()) :: keyword()
  def init(opts) do
    unless Keyword.has_key?(opts, :store) do
      raise ArgumentError, "AuthPlug requires a :store option"
    end

    opts
  end

  @doc """
  Authenticates the connection, assigning `:current_user` or halting with 401.
  """
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    store = Keyword.fetch!(opts, :store)

    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, user_id} <- TeamStore.get_user_by_token(store, token) do
      assign(conn, :current_user, user_id)
    else
      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "unauthorized"}))
        |> halt()
    end
  end
end

defmodule TeamRouter do
  @moduledoc """
  A `Plug.Router` exposing nested team-membership endpoints with optimistic
  concurrency control.

  Reads use the team version as an `ETag`; writes must present the expected
  version via an `If-Match` request header and are rejected when that version is
  stale. Requires a `:store` option and runs `AuthPlug` before route matching.
  """

  use Plug.Router

  @doc """
  Builds the router options; requires and forwards the `:store` option.
  """
  @spec init(keyword()) :: keyword()
  def init(opts) do
    unless Keyword.has_key?(opts, :store) do
      raise ArgumentError, "TeamRouter requires a :store option"
    end

    opts
  end

  @doc """
  Entry point; stashes the `:store` option on the conn and dispatches.
  """
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    store = Keyword.fetch!(opts, :store)
    conn = put_private(conn, :team_store, store)
    super(conn, opts)
  end

  plug(:store_auth)
  plug(:match)

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason
  )

  plug(:dispatch)

  get "/api/teams/:team_id/members" do
    store = conn.private.team_store
    user = conn.assigns.current_user

    cond do
      not TeamStore.team_exists?(store, team_id) ->
        send_json(conn, 404, %{error: "not_found"})

      not TeamStore.is_member?(store, team_id, user) ->
        send_json(conn, 403, %{error: "forbidden"})

      true ->
        {:ok, members} = TeamStore.list_members(store, team_id)
        {:ok, version} = TeamStore.get_version(store, team_id)

        conn
        |> Plug.Conn.put_resp_header("etag", Integer.to_string(version))
        |> send_json(200, %{members: members, version: version})
    end
  end

  post "/api/teams/:team_id/members" do
    store = conn.private.team_store
    user = conn.assigns.current_user

    cond do
      not TeamStore.team_exists?(store, team_id) ->
        send_json(conn, 404, %{error: "not_found"})

      not TeamStore.is_member?(store, team_id, user) ->
        send_json(conn, 403, %{error: "forbidden"})

      true ->
        handle_add(conn, store, team_id)
    end
  end

  match _ do
    send_json(conn, 404, %{error: "not_found"})
  end

  # -- Helpers ---------------------------------------------------------------

  @spec store_auth(Plug.Conn.t(), any()) :: Plug.Conn.t()
  defp store_auth(conn, _opts) do
    AuthPlug.call(conn, AuthPlug.init(store: conn.private.team_store))
  end

  @spec handle_add(Plug.Conn.t(), TeamStore.server(), String.t()) :: Plug.Conn.t()
  defp handle_add(conn, store, team_id) do
    case Plug.Conn.get_req_header(conn, "if-match") do
      [] ->
        send_json(conn, 428, %{error: "precondition_required"})

      [if_match | _] ->
        with_user_id(conn, store, team_id, if_match)
    end
  end

  @spec with_user_id(Plug.Conn.t(), TeamStore.server(), String.t(), String.t()) ::
          Plug.Conn.t()
  defp with_user_id(conn, store, team_id, if_match) do
    case conn.body_params do
      %{"user_id" => user_id} when is_binary(user_id) ->
        apply_add(conn, store, team_id, user_id, parse_version(if_match))

      _ ->
        send_json(conn, 400, %{error: "bad_request"})
    end
  end

  @spec apply_add(
          Plug.Conn.t(),
          TeamStore.server(),
          String.t(),
          String.t(),
          integer()
        ) :: Plug.Conn.t()
  defp apply_add(conn, store, team_id, user_id, expected_version) do
    case TeamStore.add_member_safe(store, team_id, user_id, expected_version) do
      {:ok, added, new_version} ->
        conn
        |> Plug.Conn.put_resp_header("etag", Integer.to_string(new_version))
        |> send_json(201, %{added: added, version: new_version})

      {:error, :stale} ->
        send_json(conn, 412, %{error: "precondition_failed"})

      {:error, :conflict} ->
        send_json(conn, 409, %{error: "conflict"})

      {:error, :not_found} ->
        send_json(conn, 404, %{error: "not_found"})
    end
  end

  # Interpret the header as an integer version. A non-integer value yields a
  # sentinel (-1) that can never match a real, non-negative version.
  @spec parse_version(String.t()) :: integer()
  defp parse_version(value) do
    case Integer.parse(String.trim(value)) do
      {version, ""} -> version
      _ -> -1
    end
  end

  @spec send_json(Plug.Conn.t(), non_neg_integer(), map()) :: Plug.Conn.t()
  defp send_json(conn, status, payload) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(payload))
  end
end
```

## Test harness — implement the `# TODO` test

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
    # TODO
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
