defmodule TeamStore do
  @moduledoc """
  In-memory `GenServer` holding users, capacity-bounded teams and memberships.
  All mutations are serialized through the process so capacity checks are atomic.
  """

  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  def create_user(server, id, token), do: GenServer.call(server, {:create_user, id, token})

  def create_team(server, team_id, capacity),
    do: GenServer.call(server, {:create_team, team_id, capacity})

  def add_member(server, team_id, user_id),
    do: GenServer.call(server, {:add_member, team_id, user_id})

  def get_user_by_token(server, token), do: GenServer.call(server, {:get_user_by_token, token})

  def team_exists?(server, team_id), do: GenServer.call(server, {:team_exists?, team_id})

  def is_member?(server, team_id, user_id),
    do: GenServer.call(server, {:is_member?, team_id, user_id})

  def capacity(server, team_id), do: GenServer.call(server, {:capacity, team_id})

  def size(server, team_id), do: GenServer.call(server, {:size, team_id})

  def list_members(server, team_id), do: GenServer.call(server, {:list_members, team_id})

  def join_safe(server, team_id, user_id),
    do: GenServer.call(server, {:join_safe, team_id, user_id})

  def leave_safe(server, team_id, user_id),
    do: GenServer.call(server, {:leave_safe, team_id, user_id})

  @impl true
  def init(_opts), do: {:ok, %{tokens: %{}, teams: %{}}}

  @impl true
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
  Authenticates a bearer token via `TeamStore` and assigns `:current_user`,
  or halts with a 401 JSON response.
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
  `Plug.Router` exposing capacity-bounded self-service team enrollment,
  protected by `AuthPlug`.
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