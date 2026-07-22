defmodule TeamStore do
  @moduledoc """
  In-memory `GenServer` holding users, teams, memberships and per-team version
  numbers for optimistic concurrency control.

  Every team carries a monotonically increasing version. Reads expose that
  version and writes must present the expected version so that concurrent
  clients editing the same roster cannot silently clobber each other.
  """

  use GenServer

  @typedoc "A reference to a running `TeamStore` process."
  @type server :: GenServer.server()

  @typedoc "An opaque identifier (user id, team id or bearer token)."
  @type id :: binary()

  @doc """
  Starts the store process. Accepts a `:name` option to register the process.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @doc "Stores a user identified by `id` with the given bearer `token`."
  @spec create_user(server(), id(), id()) :: :ok
  def create_user(server, id, token), do: GenServer.call(server, {:create_user, id, token})

  @doc "Creates a team at version `0`."
  @spec create_team(server(), id()) :: :ok
  def create_team(server, team_id), do: GenServer.call(server, {:create_team, team_id})

  @doc "Seeds a membership and bumps the team version. No-op for a missing team."
  @spec add_member(server(), id(), id()) :: :ok
  def add_member(server, team_id, user_id),
    do: GenServer.call(server, {:add_member, team_id, user_id})

  @doc "Resolves a bearer `token` to its user id, or `:error` when unknown."
  @spec get_user_by_token(server(), id()) :: {:ok, id()} | :error
  def get_user_by_token(server, token), do: GenServer.call(server, {:get_user_by_token, token})

  @doc "Returns whether a team exists."
  @spec team_exists?(server(), id()) :: boolean()
  def team_exists?(server, team_id), do: GenServer.call(server, {:team_exists?, team_id})

  @doc "Returns whether `user_id` is a member of `team_id`."
  @spec is_member?(server(), id(), id()) :: boolean()
  def is_member?(server, team_id, user_id),
    do: GenServer.call(server, {:is_member?, team_id, user_id})

  @doc "Returns `{:ok, version}` for an existing team, or `:error`."
  @spec version(server(), id()) :: {:ok, non_neg_integer()} | :error
  def version(server, team_id), do: GenServer.call(server, {:version, team_id})

  @doc """
  Returns `{:ok, members, version}` for an existing team, or
  `{:error, :not_found}` when the team is missing.
  """
  @spec list_members(server(), id()) ::
          {:ok, [id()], non_neg_integer()} | {:error, :not_found}
  def list_members(server, team_id), do: GenServer.call(server, {:list_members, team_id})

  @doc """
  Adds a member under an optimistic-concurrency precondition.

  Checks the precondition first: returns `{:error, :version_mismatch, current}`
  when `expected_version` differs from the team's current version, then
  `{:error, :conflict}` when the user is already a member. On success the
  version is bumped and `{:ok, user_id, new_version}` is returned.
  Returns `{:error, :not_found}` when the team is missing.
  """
  @spec add_member_safe(server(), id(), id(), non_neg_integer()) ::
          {:ok, id(), non_neg_integer()}
          | {:error, :version_mismatch, non_neg_integer()}
          | {:error, :conflict}
          | {:error, :not_found}
  def add_member_safe(server, team_id, user_id, expected_version),
    do: GenServer.call(server, {:add_member_safe, team_id, user_id, expected_version})

  @impl true
  def init(_opts), do: {:ok, %{tokens: %{}, teams: %{}}}

  @impl true
  def handle_call({:create_user, id, token}, _from, state) do
    {:reply, :ok, put_in(state.tokens[token], id)}
  end

  def handle_call({:create_team, team_id}, _from, state) do
    teams = Map.put_new(state.teams, team_id, %{members: [], version: 0})
    {:reply, :ok, %{state | teams: teams}}
  end

  def handle_call({:add_member, team_id, user_id}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      {:ok, %{members: members, version: v}} ->
        members = if user_id in members, do: members, else: members ++ [user_id]
        team = %{members: members, version: v + 1}
        {:reply, :ok, %{state | teams: Map.put(state.teams, team_id, team)}}

      :error ->
        {:reply, :ok, state}
    end
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
    members =
      case Map.fetch(state.teams, team_id) do
        {:ok, %{members: m}} -> m
        :error -> []
      end

    {:reply, user_id in members, state}
  end

  def handle_call({:version, team_id}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      {:ok, %{version: v}} -> {:reply, {:ok, v}, state}
      :error -> {:reply, :error, state}
    end
  end

  def handle_call({:list_members, team_id}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      {:ok, %{members: members, version: v}} -> {:reply, {:ok, members, v}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:add_member_safe, team_id, user_id, expected}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, %{members: members, version: v}} ->
        cond do
          expected != v ->
            {:reply, {:error, :version_mismatch, v}, state}

          user_id in members ->
            {:reply, {:error, :conflict}, state}

          true ->
            team = %{members: members ++ [user_id], version: v + 1}
            teams = Map.put(state.teams, team_id, team)
            {:reply, {:ok, user_id, v + 1}, %{state | teams: teams}}
        end
    end
  end
end

defmodule AuthPlug do
  @moduledoc """
  Authenticates a bearer token via `TeamStore` and assigns `:current_user`,
  or halts with a 401 JSON response. Accepts a `:store` option.
  """

  import Plug.Conn

  @doc "Initialises the plug, returning its options unchanged."
  @spec init(Plug.opts()) :: Plug.opts()
  def init(opts), do: opts

  @doc """
  Resolves the `authorization: Bearer <token>` header to a user and assigns
  `:current_user`, halting with a 401 JSON response when authentication fails.
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
  `Plug.Router` exposing nested team-membership resources guarded by ETag /
  If-Match optimistic concurrency control. Accepts a `:store` option.
  """

  use Plug.Router, copy_opts_to_assign: :router_opts

  plug AuthPlug
  plug :match
  plug :dispatch

  get "/api/teams/:team_id/members" do
    store = store(conn)
    user = conn.assigns.current_user

    cond do
      not TeamStore.team_exists?(store, team_id) ->
        json(conn, 404, %{error: "not_found"})

      not TeamStore.is_member?(store, team_id, user) ->
        json(conn, 403, %{error: "forbidden"})

      true ->
        {:ok, members, v} = TeamStore.list_members(store, team_id)
        json_etag(conn, 200, etag(v), %{members: members, version: v})
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
        handle_add(conn, store, team_id)
    end
  end

  match _ do
    json(conn, 404, %{error: "not_found"})
  end

  defp handle_add(conn, store, team_id) do
    case get_req_header(conn, "if-match") do
      [] ->
        json(conn, 428, %{error: "precondition_required"})

      [raw | _] ->
        case parse_version(raw) do
          :error ->
            json(conn, 412, %{error: "precondition_failed"})

          {:ok, expected} ->
            add_with_precondition(conn, store, team_id, expected)
        end
    end
  end

  defp add_with_precondition(conn, store, team_id, expected) do
    case read_user_id(conn) do
      {:ok, new_user, conn} ->
        case TeamStore.add_member_safe(store, team_id, new_user, expected) do
          {:ok, uid, nv} -> json_etag(conn, 201, etag(nv), %{added: uid, version: nv})
          {:error, :conflict} -> json(conn, 409, %{error: "conflict"})
          {:error, :not_found} -> json(conn, 404, %{error: "not_found"})
          {:error, :version_mismatch, _cur} -> json(conn, 412, %{error: "precondition_failed"})
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

  defp parse_version(raw) do
    cleaned = raw |> String.replace("\"", "") |> String.trim()

    case Integer.parse(cleaned) do
      {v, ""} -> {:ok, v}
      _ -> :error
    end
  end

  defp etag(v), do: ~s("#{v}")

  defp store(conn) do
    conn.private[:team_store] || Keyword.get(conn.assigns[:router_opts] || [], :store)
  end

  defp json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end

  defp json_etag(conn, status, etag, data) do
    conn
    |> put_resp_header("etag", etag)
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end