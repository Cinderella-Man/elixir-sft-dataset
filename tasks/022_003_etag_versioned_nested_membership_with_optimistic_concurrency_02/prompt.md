Implement the private `apply_add/5` function for `TeamRouter`. It is the final step
of a `POST /api/teams/:team_id/members` request, called once the team is known to
exist, the caller is a confirmed member, an `If-Match` header was present, and the
request body carried a string `"user_id"`.

It receives the connection, the `TeamStore` server reference, the `team_id`, the
`user_id` to add, and the `expected_version` already parsed from the `If-Match`
header (an integer). It must call `TeamStore.add_member_safe/4` with the store,
team id, user id, and expected version, then map the result onto an HTTP response
using the `send_json/3` helper:

- `{:ok, added, new_version}` → respond `201` with body `%{added: added, version:
  new_version}` and also set an `etag` response header whose value is `new_version`
  rendered as a string via `Integer.to_string/1` (use `Plug.Conn.put_resp_header/3`
  before sending).
- `{:error, :stale}` → respond `412` with body `%{error: "precondition_failed"}`.
- `{:error, :conflict}` → respond `409` with body `%{error: "conflict"}`.
- `{:error, :not_found}` → respond `404` with body `%{error: "not_found"}`.

The function must return the resulting `Plug.Conn.t()`.

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
    # TODO
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