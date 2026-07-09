# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule TeamStore do
  @moduledoc """
  In-memory `GenServer` holding users, teams and role-tagged memberships.

  State is kept entirely in process memory: a token → user index and a
  team → (`user_id` → role) map. All access goes through synchronous calls.
  """

  use GenServer

  @typedoc "A running `TeamStore` process reference."
  @type server :: GenServer.server()

  @typedoc "A membership role, one of `\"owner\"`, `\"admin\"` or `\"member\"`."
  @type role :: String.t()

  @doc """
  Starts a `TeamStore` process.

  Accepts a `:name` option which, when present, registers the process.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @doc "Stores a user identified by `id` with the given bearer `token`."
  @spec create_user(server(), term(), String.t()) :: :ok
  def create_user(server, id, token), do: GenServer.call(server, {:create_user, id, token})

  @doc "Creates an empty team identified by `team_id`."
  @spec create_team(server(), term()) :: :ok
  def create_team(server, team_id), do: GenServer.call(server, {:create_team, team_id})

  @doc "Seeds a membership for `user_id` on `team_id` with the given `role`."
  @spec add_member(server(), term(), term(), role()) :: :ok
  def add_member(server, team_id, user_id, role),
    do: GenServer.call(server, {:add_member, team_id, user_id, role})

  @doc "Looks up a user by bearer `token`, returning `{:ok, user_id}` or `:error`."
  @spec get_user_by_token(server(), String.t()) :: {:ok, term()} | :error
  def get_user_by_token(server, token), do: GenServer.call(server, {:get_user_by_token, token})

  @doc "Returns whether a team identified by `team_id` exists."
  @spec team_exists?(server(), term()) :: boolean()
  def team_exists?(server, team_id), do: GenServer.call(server, {:team_exists?, team_id})

  @doc "Returns whether `user_id` is a member of `team_id`."
  @spec is_member?(server(), term(), term()) :: boolean()
  def is_member?(server, team_id, user_id),
    do: GenServer.call(server, {:is_member?, team_id, user_id})

  @doc "Returns `{:ok, role}` for `user_id` on `team_id`, or `:error` if absent."
  @spec role_of(server(), term(), term()) :: {:ok, role()} | :error
  def role_of(server, team_id, user_id),
    do: GenServer.call(server, {:role_of, team_id, user_id})

  @doc """
  Lists the members of `team_id`.

  Returns `{:ok, [%{user_id: id, role: role}]}` or `{:error, :not_found}`.
  """
  @spec list_members(server(), term()) ::
          {:ok, [%{user_id: term(), role: role()}]} | {:error, :not_found}
  def list_members(server, team_id), do: GenServer.call(server, {:list_members, team_id})

  @doc """
  Adds `user_id` to `team_id` with `role` when possible.

  Returns `{:ok, user_id}`, `{:error, :not_found}` when the team is missing,
  or `{:error, :conflict}` when the user already belongs to the team.
  """
  @spec add_member_safe(server(), term(), term(), role()) ::
          {:ok, term()} | {:error, :not_found} | {:error, :conflict}
  def add_member_safe(server, team_id, user_id, role),
    do: GenServer.call(server, {:add_member_safe, team_id, user_id, role})

  @doc """
  Removes `user_id` from `team_id` when possible.

  Returns `{:ok, user_id}`, `{:error, :not_found}` when the team is missing,
  or `{:error, :not_member}` when the user is not on the team.
  """
  @spec remove_member_safe(server(), term(), term()) ::
          {:ok, term()} | {:error, :not_found} | {:error, :not_member}
  def remove_member_safe(server, team_id, user_id),
    do: GenServer.call(server, {:remove_member_safe, team_id, user_id})

  @impl true
  def init(_opts), do: {:ok, %{tokens: %{}, teams: %{}}}

  @impl true
  def handle_call({:create_user, id, token}, _from, state) do
    {:reply, :ok, put_in(state.tokens[token], id)}
  end

  def handle_call({:create_team, team_id}, _from, state) do
    {:reply, :ok, %{state | teams: Map.put_new(state.teams, team_id, %{})}}
  end

  def handle_call({:add_member, team_id, user_id, role}, _from, state) do
    members = state.teams |> Map.get(team_id, %{}) |> Map.put(user_id, role)
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
    {:reply, Map.has_key?(Map.get(state.teams, team_id, %{}), user_id), state}
  end

  def handle_call({:role_of, team_id, user_id}, _from, state) do
    reply =
      with {:ok, members} <- Map.fetch(state.teams, team_id),
           {:ok, role} <- Map.fetch(members, user_id) do
        {:ok, role}
      else
        :error -> :error
      end

    {:reply, reply, state}
  end

  def handle_call({:list_members, team_id}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      {:ok, members} ->
        list = Enum.map(members, fn {uid, role} -> %{user_id: uid, role: role} end)
        {:reply, {:ok, list}, state}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:add_member_safe, team_id, user_id, role}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, members} ->
        if Map.has_key?(members, user_id) do
          {:reply, {:error, :conflict}, state}
        else
          teams = Map.put(state.teams, team_id, Map.put(members, user_id, role))
          {:reply, {:ok, user_id}, %{state | teams: teams}}
        end
    end
  end

  def handle_call({:remove_member_safe, team_id, user_id}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, members} ->
        if Map.has_key?(members, user_id) do
          teams = Map.put(state.teams, team_id, Map.delete(members, user_id))
          {:reply, {:ok, user_id}, %{state | teams: teams}}
        else
          {:reply, {:error, :not_member}, state}
        end
    end
  end
end

defmodule AuthPlug do
  @moduledoc """
  Authenticates a bearer token via `TeamStore` and assigns `:current_user`,
  or halts with a 401 JSON response.
  """

  import Plug.Conn

  @doc "Initializes the plug, returning the given options unchanged."
  @spec init(Plug.opts()) :: Plug.opts()
  def init(opts), do: opts

  @doc """
  Reads the `authorization` header, expecting `Bearer <token>`.

  On success assigns `:current_user`; otherwise halts with a 401 JSON body.
  """
  @spec call(Plug.Conn.t(), Plug.opts()) :: Plug.Conn.t()
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
  `Plug.Router` exposing role-scoped nested team-membership resources.

  Read access is open to any member; mutating the roster is restricted to
  `owner`/`admin` roles, and only an `owner` may remove another `owner`.

  Plugs are initialized at runtime (`init_mode: :runtime`) so that
  `AuthPlug.init/1` is exercised on every request rather than being inlined
  at compile time.
  """

  use Plug.Router, copy_opts_to_assign: :router_opts, init_mode: :runtime

  @privileged ["owner", "admin"]
  @roles ["owner", "admin", "member"]

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

      true ->
        case TeamStore.role_of(store, team_id, user) do
          {:ok, role} when role in @privileged -> add_member(conn, store, team_id)
          _ -> json(conn, 403, %{error: "forbidden"})
        end
    end
  end

  delete "/api/teams/:team_id/members/:user_id" do
    store = store(conn)
    requester = conn.assigns.current_user

    cond do
      not TeamStore.team_exists?(store, team_id) ->
        json(conn, 404, %{error: "not_found"})

      true ->
        case TeamStore.role_of(store, team_id, requester) do
          {:ok, req_role} when req_role in @privileged ->
            remove_member(conn, store, team_id, user_id, req_role)

          _ ->
            json(conn, 403, %{error: "forbidden"})
        end
    end
  end

  match _ do
    json(conn, 404, %{error: "not_found"})
  end

  defp add_member(conn, store, team_id) do
    case read_body_params(conn) do
      {:ok, user_id, role, conn} ->
        case TeamStore.add_member_safe(store, team_id, user_id, role) do
          {:ok, uid} -> json(conn, 201, %{added: uid, role: role})
          {:error, :conflict} -> json(conn, 409, %{error: "conflict"})
          {:error, :not_found} -> json(conn, 404, %{error: "not_found"})
        end

      {:error, conn} ->
        json(conn, 400, %{error: "bad_request"})
    end
  end

  defp remove_member(conn, store, team_id, target_id, req_role) do
    case TeamStore.role_of(store, team_id, target_id) do
      :error ->
        json(conn, 404, %{error: "not_found"})

      {:ok, "owner"} when req_role != "owner" ->
        json(conn, 403, %{error: "forbidden"})

      {:ok, _} ->
        case TeamStore.remove_member_safe(store, team_id, target_id) do
          {:ok, uid} -> json(conn, 200, %{removed: uid})
          {:error, _} -> json(conn, 404, %{error: "not_found"})
        end
    end
  end

  defp read_body_params(conn) do
    {:ok, body, conn} = read_body(conn)

    case Jason.decode(body) do
      {:ok, %{"user_id" => user_id} = params} when is_binary(user_id) ->
        role = Map.get(params, "role", "member")
        if role in @roles, do: {:ok, user_id, role, conn}, else: {:error, conn}

      _ ->
        {:error, conn}
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
    # TODO
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
end
```
