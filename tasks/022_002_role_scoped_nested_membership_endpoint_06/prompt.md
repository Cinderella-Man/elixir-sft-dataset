# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `create_user` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me a set of Elixir modules that implement a **role-scoped** nested resource endpoint for team membership, using only `Plug` and standard OTP (no Phoenix, no database, no external dependencies beyond `plug` and `jason`).

Unlike a flat membership model, every membership now carries a **role** — one of `"owner"`, `"admin"`, or `"member"`. Read access is open to any member, but mutating the roster (adding or removing members) is restricted to privileged roles, and owners are protected from being removed by mere admins.

I need these modules:

**`TeamStore`** — a GenServer holding all state in memory (users, teams, and role-tagged memberships). Public functions:

- `TeamStore.start_link(opts)` — starts the process. Accepts a `:name` option.
- `TeamStore.create_user(server, id, token)` — stores a user with a bearer token. Returns `:ok`.
- `TeamStore.create_team(server, team_id)` — creates a team. Returns `:ok`.
- `TeamStore.add_member(server, team_id, user_id, role)` — seeds a membership with a role. Returns `:ok`.
- `TeamStore.get_user_by_token(server, token)` — returns `{:ok, user_id}` or `:error`.
- `TeamStore.team_exists?(server, team_id)` — returns `true`/`false`.
- `TeamStore.is_member?(server, team_id, user_id)` — returns `true`/`false`.
- `TeamStore.role_of(server, team_id, user_id)` — returns `{:ok, role}` or `:error`.
- `TeamStore.list_members(server, team_id)` — returns `{:ok, [%{user_id: id, role: role}]}` or `{:error, :not_found}`.
- `TeamStore.add_member_safe(server, team_id, user_id, role)` — adds a member with a role if the team exists and the user isn't already on the team. Returns `{:ok, user_id}`, `{:error, :not_found}`, or `{:error, :conflict}`.
- `TeamStore.remove_member_safe(server, team_id, user_id)` — removes a member. Returns `{:ok, user_id}`, `{:error, :not_found}` (no team), or `{:error, :not_member}`.

**`AuthPlug`** — reads the `authorization` header, expects `Bearer <token>`, looks the user up via `TeamStore.get_user_by_token/2`, and assigns `:current_user`. On missing/invalid token, halts with 401 JSON `{"error": "unauthorized"}`. Accepts a `:store` option at init; `AuthPlug.init/1` must return the given options unchanged (so the same value can be passed straight to `call/2`).

**`TeamRouter`** — a `Plug.Router` accepting a `:store` option, plugging `AuthPlug` before matching. Endpoints:

- `GET /api/teams/:team_id/members` — 404 `{"error":"not_found"}` if the team is missing; 403 `{"error":"forbidden"}` if the caller isn't a member; otherwise 200 `{"members": [{"user_id": ..., "role": ...}]}`.

- `POST /api/teams/:team_id/members` — body `{"user_id": "...", "role": "..."}`. The body must be JSON carrying a string `user_id`; a missing or non-string `user_id` (or otherwise malformed body) yields 400 `{"error":"bad_request"}`. `role` is optional and defaults to `"member"`; it must be one of the three valid roles or the response is 400 `{"error":"bad_request"}`. 404 if the team is missing. If the caller is **not** an `owner` or `admin` of the team (including non-members), 403 `{"error":"forbidden"}`. 409 `{"error":"conflict"}` if the target is already a member. On success 201 `{"added": user_id, "role": role}`.

- `DELETE /api/teams/:team_id/members/:user_id` — 404 if the team is missing. If the caller isn't an `owner`/`admin`, 403. If the target isn't a member, 404 `{"error":"not_found"}`. An `admin` may **not** remove an `owner` (403); only an `owner` may remove an `owner`. On success 200 `{"removed": user_id}`.

All responses must be `application/json`. Give me all modules in a single file, using only `plug`, `jason`, and the OTP standard library.

## The module with `create_user` missing

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

  def create_user(server, id, token) do
    # TODO
  end

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

Give me only the complete implementation of `create_user` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
