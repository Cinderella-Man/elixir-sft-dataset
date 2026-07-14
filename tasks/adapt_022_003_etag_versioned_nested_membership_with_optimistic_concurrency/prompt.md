# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

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

Write me a set of Elixir modules that implement **nested resource endpoints for team membership with optimistic concurrency control**, using only `Plug` and standard OTP (no Phoenix, no database, no external dependencies beyond `plug` and `jason`).

Every team carries a monotonically increasing **version** number. Mutations must present the version they expect to update via an `If-Match` request header; if the version has moved on, the write is rejected. This lets concurrent clients detect lost updates.

I need these modules:

**`TeamStore`** — a GenServer that holds all application state in memory (users, teams, memberships, and per-team version numbers). It should support these public functions:

- `TeamStore.start_link(opts)` — starts the process. Accepts a `:name` option for registration.
- `TeamStore.create_user(server, id, token)` — stores a user with the given ID and bearer token. Returns `:ok`.
- `TeamStore.create_team(server, team_id)` — creates a team with an empty member list and **version `0`**. Returns `:ok`.
- `TeamStore.add_member(server, team_id, user_id)` — adds a user to a team directly (for seeding). Adding a not-yet-present user **increments the team's version by 1**; adding a user already on the team is a no-op that leaves the version unchanged. Returns `:ok`.
- `TeamStore.get_user_by_token(server, token)` — returns `{:ok, user_id}` or `:error`.
- `TeamStore.team_exists?(server, team_id)` — returns `true` or `false`.
- `TeamStore.is_member?(server, team_id, user_id)` — returns `true` or `false`.
- `TeamStore.get_version(server, team_id)` — returns `{:ok, version}` or `{:error, :not_found}`.
- `TeamStore.list_members(server, team_id)` — returns `{:ok, list_of_user_ids}` or `{:error, :not_found}`.
- `TeamStore.add_member_safe(server, team_id, user_id, expected_version)` — atomically adds a member only if all of the following hold. Checks are performed in this order:
  1. If the team does not exist, returns `{:error, :not_found}`.
  2. If `expected_version` does not equal the team's current version, returns `{:error, :stale}`.
  3. If the user is already a member, returns `{:error, :conflict}`.
  4. Otherwise it appends the user, increments the version by 1, and returns `{:ok, user_id, new_version}`.

**`AuthPlug`** — a Plug that reads the `authorization` header, expects `Bearer <token>`, looks the user up via `TeamStore.get_user_by_token/2`, and assigns `:current_user` to the conn. If the token is missing or invalid, it halts the connection with a 401 JSON response `{"error": "unauthorized"}`. It should accept a `:store` option at init time to know which TeamStore process to call.

**`TeamRouter`** — a `Plug.Router` that serves the following endpoints. It should accept a `:store` option and plug `AuthPlug` before route matching.

- `GET /api/teams/:team_id/members` — If the team doesn't exist, return 404 `{"error": "not_found"}`. If the current user is not a member of the team, return 403 `{"error": "forbidden"}`. Otherwise return 200 `{"members": [list_of_user_ids], "version": version}` and set a response header `ETag` whose value is the version rendered as a string (e.g. version `2` → `ETag: 2`).

- `POST /api/teams/:team_id/members` — Reads a JSON body with `{"user_id": "..."}`. The response is decided in this order:
  1. If the team doesn't exist, return 404 `{"error": "not_found"}`.
  2. If the current user is not a member of the team, return 403 `{"error": "forbidden"}`.
  3. If there is no `If-Match` request header, return 428 `{"error": "precondition_required"}`.
  4. If the body is missing a string `"user_id"` field, return 400 `{"error": "bad_request"}`.
  5. Interpret the `If-Match` header value as the expected version (an integer; a non-integer value is treated as a version that can never match). Call `add_member_safe/4` with it. Map its result: `{:error, :stale}` → 412 `{"error": "precondition_failed"}`; `{:error, :conflict}` → 409 `{"error": "conflict"}`; `{:error, :not_found}` → 404 `{"error": "not_found"}`; `{:ok, user_id, new_version}` → 201 `{"added": user_id, "version": new_version}` with a response header `ETag` equal to the new version rendered as a string.

Because every successful write bumps the version, a client that reads the version, then performs a write, invalidates any other client still holding the old version — a second write presenting the now-stale version gets 412.

All error and success responses must be `application/json`. Give me all modules in a single file. Use only `plug`, `jason`, and the OTP standard library.
