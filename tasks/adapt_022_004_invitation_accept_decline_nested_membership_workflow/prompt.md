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

Write me a set of Elixir modules that implement a nested resource endpoint for team membership built around an **invitation / RSVP workflow**, using only `Plug` and standard OTP (no Phoenix, no database, no external dependencies beyond `plug` and `jason`).

Instead of adding members directly through the API, a team member *invites* another user. That creates a **pending invitation**. The invited user must then *accept* the invitation themselves before they become an actual member, or *decline* it to drop the invitation. This means a membership record can be in one of two visible states: **pending** (invited but not yet joined) and **active** (a full member).

I need these modules:

**`TeamStore`** — a GenServer that holds all application state in memory (users, teams, active members, and pending invitations). It should support these public functions:

- `TeamStore.start_link(opts)` — starts the process. Accepts a `:name` option for registration.
- `TeamStore.create_user(server, id, token)` — stores a user with the given ID and bearer token. Returns `:ok`.
- `TeamStore.create_team(server, team_id)` — creates a team with no members and no invitations. Returns `:ok`.
- `TeamStore.add_member(server, team_id, user_id)` — adds a user directly as an active member (for seeding). Returns `:ok`.
- `TeamStore.get_user_by_token(server, token)` — returns `{:ok, user_id}` or `:error`.
- `TeamStore.team_exists?(server, team_id)` — returns `true` or `false`.
- `TeamStore.is_member?(server, team_id, user_id)` — returns `true` if the user is an active member, else `false`.
- `TeamStore.is_invited?(server, team_id, user_id)` — returns `true` if the user has a pending invitation for the team, else `false`.
- `TeamStore.list_members(server, team_id)` — returns `{:ok, list_of_active_member_ids}` or `{:error, :not_found}` if the team does not exist.
- `TeamStore.list_invitations(server, team_id)` — returns `{:ok, list_of_pending_user_ids}` or `{:error, :not_found}` if the team does not exist.
- `TeamStore.invite_member(server, team_id, user_id)` — creates a pending invitation for `user_id`. Returns `{:error, :not_found}` if the team does not exist, `{:error, :conflict}` if the user is already an active member, `{:error, :already_invited}` if the user already has a pending invitation, and `{:ok, user_id}` on success.
- `TeamStore.accept_invite(server, team_id, user_id)` — turns a pending invitation into an active membership: it removes the pending invitation and adds the user as an active member. Returns `{:error, :not_found}` if the team does not exist, `{:error, :no_invitation}` if the user has no pending invitation for the team, and `{:ok, user_id}` on success.
- `TeamStore.decline_invite(server, team_id, user_id)` — removes a pending invitation **without** adding the user as a member. Returns `{:error, :not_found}` if the team does not exist, `{:error, :no_invitation}` if the user has no pending invitation for the team, and `{:ok, user_id}` on success.

**`AuthPlug`** — a Plug that reads the `authorization` header, expects `Bearer <token>`, looks the user up via `TeamStore.get_user_by_token/2`, and assigns `:current_user` to the conn. If the token is missing or invalid, it halts the connection with a 401 JSON response `{"error": "unauthorized"}`. It should accept a `:store` option at init time to know which TeamStore process to call. Note: authentication only verifies the token maps to a real user — it does **not** require the user to be a member of any team.

**`TeamRouter`** — a `Plug.Router` that serves the following endpoints. It should accept a `:store` option and plug `AuthPlug` before route matching.

- `GET /api/teams/:team_id/members` — If the team doesn't exist, return 404 `{"error": "not_found"}`. If the current user is not an active member of the team, return 403 `{"error": "forbidden"}`. Otherwise return 200 `{"members": [list_of_active_member_ids]}`.

- `GET /api/teams/:team_id/invitations` — Same 404/403 rules as the members list (only an active member of the team may view its pending invitations). Otherwise return 200 `{"invitations": [list_of_pending_user_ids]}`.

- `POST /api/teams/:team_id/invitations` — Reads a JSON body with `{"user_id": "..."}`. If the team doesn't exist, return 404 `{"error": "not_found"}`. If the current user is not an active member of the team, return 403 `{"error": "forbidden"}` (only members may invite). If the body is missing a string `user_id`, return 400 `{"error": "bad_request"}`. If the invited user is already an active member, return 409 `{"error": "conflict"}`. If the invited user already has a pending invitation, return 409 `{"error": "already_invited"}`. On success, return 201 `{"invited": user_id}`.

- `POST /api/teams/:team_id/invitations/:user_id/accept` — The current user accepts *their own* invitation. If the team doesn't exist, return 404 `{"error": "not_found"}`. If the current user is not the same as the `:user_id` in the path, return 403 `{"error": "forbidden"}` (a user may only accept their own invitation). If the user has no pending invitation for the team, return 409 `{"error": "no_invitation"}`. On success, the user becomes an active member and the pending invitation is removed; return 200 `{"accepted": user_id}`.

- `POST /api/teams/:team_id/invitations/:user_id/decline` — The current user declines *their own* invitation. Same 404 (team missing) and 403 (not your own invitation) rules as accept. If the user has no pending invitation for the team, return 409 `{"error": "no_invitation"}`. On success, the pending invitation is removed and the user does **not** become a member; return 200 `{"declined": user_id}`.

For the endpoints above, the checks must be applied in the order they are listed (team existence first, then authorization, then the operation-specific outcomes).

All error and success responses must be `application/json`. Give me all modules in a single file. Use only `plug`, `jason`, and the OTP standard library.
