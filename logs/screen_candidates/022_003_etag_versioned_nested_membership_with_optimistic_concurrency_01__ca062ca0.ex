defmodule TeamStore do
  @moduledoc """
  In-memory state holder for users, teams, memberships, and per-team versions.

  Every team carries a monotonically increasing version number. Direct seeding
  helpers (`add_member/3`) and the concurrency-safe `add_member_safe/4` both bump
  the version whenever a new member is actually appended, which lets concurrent
  clients detect lost updates via optimistic concurrency control.

  All state lives in a single `GenServer` so that reads and writes are serialized
  and the version checks performed by `add_member_safe/4` are fully atomic.
  """

  use GenServer

  @typedoc "A running TeamStore process reference (pid or registered name)."
  @type server :: GenServer.server()

  @typedoc "Internal server state."
  @type state :: %{users: %{String.t() => String.t()}, teams: %{String.t() => team()}}

  @typedoc "Internal per-team record."
  @type team :: %{members: [String.t()], version: non_neg_integer()}

  @doc """
  Starts the store process.

  Accepts a `:name` option used to register the process. Any other options are
  ignored.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    gen_opts =
      case Keyword.fetch(opts, :name) do
        {:ok, name} -> [name: name]
        :error -> []
      end

    GenServer.start_link(__MODULE__, :ok, gen_opts)
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

  If the team already exists it is left untouched.
  """
  @spec create_team(server(), String.t()) :: :ok
  def create_team(server, team_id) do
    GenServer.call(server, {:create_team, team_id})
  end

  @doc """
  Adds a user to a team directly, for seeding.

  Adding a not-yet-present user increments the team's version by 1. Adding a user
  already on the team is a no-op that leaves the version unchanged. A missing team
  is a no-op.
  """
  @spec add_member(server(), String.t(), String.t()) :: :ok
  def add_member(server, team_id, user_id) do
    GenServer.call(server, {:add_member, team_id, user_id})
  end

  @doc """
  Looks up a user by bearer `token`.
  """
  @spec get_user_by_token(server(), String.t()) :: {:ok, String.t()} | :error
  def get_user_by_token(server, token) do
    GenServer.call(server, {:get_user_by_token, token})
  end

  @doc """
  Returns whether the given team exists.
  """
  @spec team_exists?(server(), String.t()) :: boolean()
  def team_exists?(server, team_id) do
    GenServer.call(server, {:team_exists?, team_id})
  end

  @doc """
  Returns whether `user_id` is a member of the given team.
  """
  @spec is_member?(server(), String.t(), String.t()) :: boolean()
  def is_member?(server, team_id, user_id) do
    GenServer.call(server, {:is_member?, team_id, user_id})
  end

  @doc """
  Returns the current version of a team, or `{:error, :not_found}`.
  """
  @spec get_version(server(), String.t()) :: {:ok, non_neg_integer()} | {:error, :not_found}
  def get_version(server, team_id) do
    GenServer.call(server, {:get_version, team_id})
  end

  @doc """
  Returns the member list of a team, or `{:error, :not_found}`.
  """
  @spec list_members(server(), String.t()) :: {:ok, [String.t()]} | {:error, :not_found}
  def list_members(server, team_id) do
    GenServer.call(server, {:list_members, team_id})
  end

  @doc """
  Atomically adds a member using optimistic concurrency control.

  Checks are performed in order:

    1. missing team -> `{:error, :not_found}`;
    2. `expected_version` mismatch -> `{:error, :stale}`;
    3. user already a member -> `{:error, :conflict}`;
    4. otherwise the user is appended, the version is incremented by 1, and
       `{:ok, user_id, new_version}` is returned.
  """
  @spec add_member_safe(server(), String.t(), String.t(), integer()) ::
          {:ok, String.t(), non_neg_integer()}
          | {:error, :not_found | :stale | :conflict}
  def add_member_safe(server, team_id, user_id, expected_version) do
    GenServer.call(server, {:add_member_safe, team_id, user_id, expected_version})
  end

  @impl GenServer
  def init(:ok) do
    {:ok, %{users: %{}, teams: %{}}}
  end

  @impl GenServer
  def handle_call({:create_user, id, token}, _from, state) do
    {:reply, :ok, %{state | users: Map.put(state.users, token, id)}}
  end

  def handle_call({:create_team, team_id}, _from, state) do
    teams = Map.put_new(state.teams, team_id, %{members: [], version: 0})
    {:reply, :ok, %{state | teams: teams}}
  end

  def handle_call({:add_member, team_id, user_id}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      {:ok, team} ->
        if user_id in team.members do
          {:reply, :ok, state}
        else
          updated = %{team | members: team.members ++ [user_id], version: team.version + 1}
          {:reply, :ok, %{state | teams: Map.put(state.teams, team_id, updated)}}
        end

      :error ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:get_user_by_token, token}, _from, state) do
    case Map.fetch(state.users, token) do
      {:ok, id} -> {:reply, {:ok, id}, state}
      :error -> {:reply, :error, state}
    end
  end

  def handle_call({:team_exists?, team_id}, _from, state) do
    {:reply, Map.has_key?(state.teams, team_id), state}
  end

  def handle_call({:is_member?, team_id, user_id}, _from, state) do
    member? =
      case Map.fetch(state.teams, team_id) do
        {:ok, team} -> user_id in team.members
        :error -> false
      end

    {:reply, member?, state}
  end

  def handle_call({:get_version, team_id}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      {:ok, team} -> {:reply, {:ok, team.version}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:list_members, team_id}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      {:ok, team} -> {:reply, {:ok, team.members}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:add_member_safe, team_id, user_id, expected_version}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, team} ->
        cond do
          team.version != expected_version ->
            {:reply, {:error, :stale}, state}

          user_id in team.members ->
            {:reply, {:error, :conflict}, state}

          true ->
            new_version = team.version + 1
            updated = %{team | members: team.members ++ [user_id], version: new_version}
            teams = Map.put(state.teams, team_id, updated)
            {:reply, {:ok, user_id, new_version}, %{state | teams: teams}}
        end
    end
  end
end

defmodule AuthPlug do
  @moduledoc """
  Bearer-token authentication plug.

  Reads the `authorization` request header, expects a `Bearer <token>` value, and
  resolves it through `TeamStore.get_user_by_token/2`. On success it assigns
  `:current_user` and also stashes the store under `conn.private.team_store` for
  downstream route handlers. On any failure it halts with a 401 JSON response.

  Expects a `:store` option (typically forwarded via `builder_opts/0`) naming the
  `TeamStore` process to query.
  """

  @behaviour Plug

  import Plug.Conn

  @doc """
  Initializes the plug, returning its options unchanged.
  """
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @doc """
  Authenticates the request, assigning `:current_user` or halting with 401.
  """
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    store = Keyword.fetch!(opts, :store)
    conn = put_private(conn, :team_store, store)

    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> authenticate(conn, store, token)
      _ -> unauthorized(conn)
    end
  end

  @spec authenticate(Plug.Conn.t(), TeamStore.server(), String.t()) :: Plug.Conn.t()
  defp authenticate(conn, store, token) do
    case TeamStore.get_user_by_token(store, token) do
      {:ok, user_id} -> assign(conn, :current_user, user_id)
      :error -> unauthorized(conn)
    end
  end

  @spec unauthorized(Plug.Conn.t()) :: Plug.Conn.t()
  defp unauthorized(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, Jason.encode!(%{error: "unauthorized"}))
    |> halt()
  end
end

defmodule TeamRouter do
  @moduledoc """
  HTTP router for nested team-membership resources with optimistic concurrency.

  Runs `AuthPlug` before route matching (forwarding the router's `:store` option
  via `builder_opts/0`) so that every request is authenticated and the target
  `TeamStore` process is available under `conn.private.team_store`.

  Endpoints:

    * `GET /api/teams/:team_id/members` — list members plus the current version,
      exposed as an `ETag` response header.
    * `POST /api/teams/:team_id/members` — add a member guarded by the `If-Match`
      request header, which must equal the team's current version.

  All responses are `application/json`.
  """

  use Plug.Router

  plug AuthPlug, builder_opts()
  plug :match
  plug :dispatch

  get "/api/teams/:team_id/members" do
    store = conn.private.team_store
    handle_list(conn, store, team_id, conn.assigns.current_user)
  end

  post "/api/teams/:team_id/members" do
    store = conn.private.team_store
    handle_add(conn, store, team_id, conn.assigns.current_user)
  end

  match _ do
    send_json(conn, 404, %{error: "not_found"})
  end

  @spec handle_list(Plug.Conn.t(), TeamStore.server(), String.t(), String.t()) ::
          Plug.Conn.t()
  defp handle_list(conn, store, team_id, user) do
    cond do
      not TeamStore.team_exists?(store, team_id) ->
        send_json(conn, 404, %{error: "not_found"})

      not TeamStore.is_member?(store, team_id, user) ->
        send_json(conn, 403, %{error: "forbidden"})

      true ->
        {:ok, members} = TeamStore.list_members(store, team_id)
        {:ok, version} = TeamStore.get_version(store, team_id)

        conn
        |> put_resp_header("etag", Integer.to_string(version))
        |> send_json(200, %{members: members, version: version})
    end
  end

  @spec handle_add(Plug.Conn.t(), TeamStore.server(), String.t(), String.t()) ::
          Plug.Conn.t()
  defp handle_add(conn, store, team_id, user) do
    cond do
      not TeamStore.team_exists?(store, team_id) ->
        send_json(conn, 404, %{error: "not_found"})

      not TeamStore.is_member?(store, team_id, user) ->
        send_json(conn, 403, %{error: "forbidden"})

      get_req_header(conn, "if-match") == [] ->
        send_json(conn, 428, %{error: "precondition_required"})

      true ->
        add_with_body(conn, store, team_id)
    end
  end

  @spec add_with_body(Plug.Conn.t(), TeamStore.server(), String.t()) :: Plug.Conn.t()
  defp add_with_body(conn, store, team_id) do
    {:ok, raw, conn} = read_body(conn)

    case decode_user_id(raw) do
      {:ok, user_id} ->
        apply_add(conn, store, team_id, user_id, parse_if_match(conn))

      :error ->
        send_json(conn, 400, %{error: "bad_request"})
    end
  end

  @spec apply_add(Plug.Conn.t(), TeamStore.server(), String.t(), String.t(), integer()) ::
          Plug.Conn.t()
  defp apply_add(conn, store, team_id, user_id, expected) do
    case TeamStore.add_member_safe(store, team_id, user_id, expected) do
      {:ok, added, version} ->
        conn
        |> put_resp_header("etag", Integer.to_string(version))
        |> send_json(201, %{added: added, version: version})

      {:error, :stale} ->
        send_json(conn, 412, %{error: "precondition_failed"})

      {:error, :conflict} ->
        send_json(conn, 409, %{error: "conflict"})

      {:error, :not_found} ->
        send_json(conn, 404, %{error: "not_found"})
    end
  end

  @spec decode_user_id(binary()) :: {:ok, String.t()} | :error
  defp decode_user_id(raw) do
    case Jason.decode(raw) do
      {:ok, %{"user_id" => user_id}} when is_binary(user_id) -> {:ok, user_id}
      _ -> :error
    end
  end

  @spec parse_if_match(Plug.Conn.t()) :: integer()
  defp parse_if_match(conn) do
    case get_req_header(conn, "if-match") do
      [value | _] ->
        case Integer.parse(value) do
          {int, ""} -> int
          _ -> -1
        end

      [] ->
        -1
    end
  end

  @spec send_json(Plug.Conn.t(), non_neg_integer(), map()) :: Plug.Conn.t()
  defp send_json(conn, status, payload) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(payload))
  end
end