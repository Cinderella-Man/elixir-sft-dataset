# Rework this solution for a changed brief

The module below is a complete, tested solution to a neighboring task. Treat
it as your starting codebase, not as a suggestion — carry over what still
fits and rewrite what the new brief demands. Where old code and the new
specification conflict (module name, public API, behavior, constraints,
output format), the new specification is authoritative. Return the complete
final result.

## Existing code (your starting point)

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

## New specification

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
