defmodule TeamStore do
  @moduledoc """
  In-memory `GenServer` holding users, capacity-bounded teams and memberships.

  All mutations are serialized through the process so that the capacity
  check-and-insert for `join_safe/3` is a single atomic step, even when many
  join requests race concurrently.
  """

  use GenServer

  @typedoc "A running server reference (pid or registered name)."
  @type server :: GenServer.server()

  @doc """
  Starts the store process.

  Accepts a `:name` option that, when present, registers the process.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @doc "Stores a user identified by `id` with the given bearer `token`."
  @spec create_user(server(), term(), String.t()) :: :ok
  def create_user(server, id, token), do: GenServer.call(server, {:create_user, id, token})

  @doc "Creates a team `team_id` with a maximum size of `capacity`."
  @spec create_team(server(), term(), non_neg_integer()) :: :ok
  def create_team(server, team_id, capacity),
    do: GenServer.call(server, {:create_team, team_id, capacity})

  @doc "Seeds a membership directly, without any capacity check."
  @spec add_member(server(), term(), term()) :: :ok
  def add_member(server, team_id, user_id),
    do: GenServer.call(server, {:add_member, team_id, user_id})

  @doc "Resolves a bearer `token` to `{:ok, user_id}` or `:error`."
  @spec get_user_by_token(server(), String.t()) :: {:ok, term()} | :error
  def get_user_by_token(server, token), do: GenServer.call(server, {:get_user_by_token, token})

  @doc "Returns whether the team `team_id` exists."
  @spec team_exists?(server(), term()) :: boolean()
  def team_exists?(server, team_id), do: GenServer.call(server, {:team_exists?, team_id})

  @doc "Returns whether `user_id` is enrolled in team `team_id`."
  @spec is_member?(server(), term(), term()) :: boolean()
  def is_member?(server, team_id, user_id),
    do: GenServer.call(server, {:is_member?, team_id, user_id})

  @doc "Returns `{:ok, capacity}` for the team, or `:error` if it is missing."
  @spec capacity(server(), term()) :: {:ok, non_neg_integer()} | :error
  def capacity(server, team_id), do: GenServer.call(server, {:capacity, team_id})

  @doc "Returns `{:ok, count}` of current members, or `:error` if missing."
  @spec size(server(), term()) :: {:ok, non_neg_integer()} | :error
  def size(server, team_id), do: GenServer.call(server, {:size, team_id})

  @doc "Returns `{:ok, members}` or `{:error, :not_found}` for the team."
  @spec list_members(server(), term()) :: {:ok, [term()]} | {:error, :not_found}
  def list_members(server, team_id), do: GenServer.call(server, {:list_members, team_id})

  @doc """
  Atomically enrolls `user_id` into `team_id`.

  Returns `{:error, :not_found}` when the team is missing,
  `{:error, :already_member}` when already enrolled, `{:error, :full}` when at
  capacity, and otherwise `{:ok, user_id, new_size}`.
  """
  @spec join_safe(server(), term(), term()) ::
          {:ok, term(), non_neg_integer()}
          | {:error, :not_found | :already_member | :full}
  def join_safe(server, team_id, user_id),
    do: GenServer.call(server, {:join_safe, team_id, user_id})

  @doc """
  Withdraws `user_id` from `team_id`.

  Returns `{:error, :not_found}` when the team is missing,
  `{:error, :not_member}` when not enrolled, and otherwise
  `{:ok, user_id, new_size}`.
  """
  @spec leave_safe(server(), term(), term()) ::
          {:ok, term(), non_neg_integer()}
          | {:error, :not_found | :not_member}
  def leave_safe(server, team_id, user_id),
    do: GenServer.call(server, {:leave_safe, team_id, user_id})

  @impl true
  @doc false
  @spec init(keyword()) :: {:ok, map()}
  def init(_opts), do: {:ok, %{tokens: %{}, teams: %{}}}

  @impl true
  @doc false
  @spec handle_call(term(), GenServer.from(), map()) :: {:reply, term(), map()}
  def handle_call({:create_user, id, token}, _from, state) do
    {:reply, :ok, put_in(state.tokens[token], id)}
  end

  def handle_call({:create_team, team_id, capacity}, _from, state) do
    teams = Map.put_new(state.teams, team_id, %{members: [], capacity: capacity})
    {:reply, :ok, %{state | teams: teams}}
  end

  def handle_call({:add_member, team_id, user_id}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      {:ok, %{members: members} = team} ->
        members = if user_id in members, do: members, else: members ++ [user_id]
        teams = Map.put(state.teams, team_id, %{team | members: members})
        {:reply, :ok, %{state | teams: teams}}

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

  def handle_call({:capacity, team_id}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      {:ok, %{capacity: c}} -> {:reply, {:ok, c}, state}
      :error -> {:reply, :error, state}
    end
  end

  def handle_call({:size, team_id}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      {:ok, %{members: m}} -> {:reply, {:ok, length(m)}, state}
      :error -> {:reply, :error, state}
    end
  end

  def handle_call({:list_members, team_id}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      {:ok, %{members: m}} -> {:reply, {:ok, m}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:join_safe, team_id, user_id}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, %{members: members, capacity: cap} = team} ->
        cond do
          user_id in members ->
            {:reply, {:error, :already_member}, state}

          length(members) >= cap ->
            {:reply, {:error, :full}, state}

          true ->
            members = members ++ [user_id]
            teams = Map.put(state.teams, team_id, %{team | members: members})
            {:reply, {:ok, user_id, length(members)}, %{state | teams: teams}}
        end
    end
  end

  def handle_call({:leave_safe, team_id, user_id}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, %{members: members} = team} ->
        if user_id in members do
          members = List.delete(members, user_id)
          teams = Map.put(state.teams, team_id, %{team | members: members})
          {:reply, {:ok, user_id, length(members)}, %{state | teams: teams}}
        else
          {:reply, {:error, :not_member}, state}
        end
    end
  end
end

defmodule AuthPlug do
  @moduledoc """
  A `Plug` that authenticates a bearer token via `TeamStore`.

  On success it assigns `:current_user`; otherwise it halts the connection with
  a 401 JSON response. Accepts a `:store` option identifying the `TeamStore`.
  """

  import Plug.Conn

  @doc "Returns the plug options unchanged."
  @spec init(Plug.opts()) :: Plug.opts()
  def init(opts), do: opts

  @doc """
  Reads the `authorization: Bearer <token>` header, resolves the user and
  assigns `:current_user`, or halts with 401 `{"error":"unauthorized"}`.
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
  `Plug.Router` exposing capacity-bounded self-service team enrollment.

  Every request is authenticated by `AuthPlug` before matching. All responses
  are encoded as `application/json`. Accepts a `:store` option identifying the
  `TeamStore` backing the endpoints.
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
        {:ok, members} = TeamStore.list_members(store, team_id)
        {:ok, cap} = TeamStore.capacity(store, team_id)
        json(conn, 200, %{members: members, size: length(members), capacity: cap})
    end
  end

  post "/api/teams/:team_id/join" do
    store = store(conn)
    user = conn.assigns.current_user

    case TeamStore.join_safe(store, team_id, user) do
      {:ok, uid, size} -> json(conn, 201, %{joined: uid, size: size})
      {:error, :already_member} -> json(conn, 409, %{error: "already_member"})
      {:error, :full} -> json(conn, 409, %{error: "team_full"})
      {:error, :not_found} -> json(conn, 404, %{error: "not_found"})
    end
  end

  delete "/api/teams/:team_id/join" do
    store = store(conn)
    user = conn.assigns.current_user

    case TeamStore.leave_safe(store, team_id, user) do
      {:ok, uid, size} -> json(conn, 200, %{left: uid, size: size})
      {:error, :not_member} -> json(conn, 409, %{error: "not_member"})
      {:error, :not_found} -> json(conn, 404, %{error: "not_found"})
    end
  end

  match _ do
    json(conn, 404, %{error: "not_found"})
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