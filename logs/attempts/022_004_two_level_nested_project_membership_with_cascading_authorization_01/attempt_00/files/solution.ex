defmodule TeamStore do
  @moduledoc """
  In-memory `GenServer` holding users, teams, team memberships, projects and
  project memberships. Projects are nested under teams; project membership is a
  subset of team membership.
  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  def create_user(server, id, token), do: GenServer.call(server, {:create_user, id, token})

  def create_team(server, team_id), do: GenServer.call(server, {:create_team, team_id})

  def add_member(server, team_id, user_id),
    do: GenServer.call(server, {:add_member, team_id, user_id})

  def create_project(server, team_id, project_id),
    do: GenServer.call(server, {:create_project, team_id, project_id})

  def add_project_member(server, team_id, project_id, user_id),
    do: GenServer.call(server, {:add_project_member, team_id, project_id, user_id})

  def get_user_by_token(server, token), do: GenServer.call(server, {:get_user_by_token, token})

  def team_exists?(server, team_id), do: GenServer.call(server, {:team_exists?, team_id})

  def is_member?(server, team_id, user_id),
    do: GenServer.call(server, {:is_member?, team_id, user_id})

  def project_exists?(server, team_id, project_id),
    do: GenServer.call(server, {:project_exists?, team_id, project_id})

  def is_project_member?(server, team_id, project_id, user_id),
    do: GenServer.call(server, {:is_project_member?, team_id, project_id, user_id})

  def list_projects(server, team_id), do: GenServer.call(server, {:list_projects, team_id})

  def list_project_members(server, team_id, project_id),
    do: GenServer.call(server, {:list_project_members, team_id, project_id})

  def add_project_member_safe(server, team_id, project_id, user_id),
    do: GenServer.call(server, {:add_project_member_safe, team_id, project_id, user_id})

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    {:ok, %{tokens: %{}, teams: %{}, projects: %{}}}
  end

  @impl true
  def handle_call({:create_user, id, token}, _from, state) do
    {:reply, :ok, put_in(state.tokens[token], id)}
  end

  def handle_call({:create_team, team_id}, _from, state) do
    teams = Map.put_new(state.teams, team_id, [])
    projects = Map.put_new(state.projects, team_id, %{})
    {:reply, :ok, %{state | teams: teams, projects: projects}}
  end

  def handle_call({:add_member, team_id, user_id}, _from, state) do
    members = Map.get(state.teams, team_id, [])
    members = if user_id in members, do: members, else: members ++ [user_id]
    {:reply, :ok, %{state | teams: Map.put(state.teams, team_id, members)}}
  end

  def handle_call({:create_project, team_id, project_id}, _from, state) do
    team_projects = Map.get(state.projects, team_id, %{})
    team_projects = Map.put_new(team_projects, project_id, [])
    {:reply, :ok, %{state | projects: Map.put(state.projects, team_id, team_projects)}}
  end

  def handle_call({:add_project_member, team_id, project_id, user_id}, _from, state) do
    {:reply, :ok, put_project_member(state, team_id, project_id, user_id)}
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

  def handle_call({:project_exists?, team_id, project_id}, _from, state) do
    team_projects = Map.get(state.projects, team_id, %{})
    {:reply, Map.has_key?(team_projects, project_id), state}
  end

  def handle_call({:is_project_member?, team_id, project_id, user_id}, _from, state) do
    team_projects = Map.get(state.projects, team_id, %{})
    members = Map.get(team_projects, project_id, [])
    {:reply, user_id in members, state}
  end

  def handle_call({:list_projects, team_id}, _from, state) do
    if Map.has_key?(state.teams, team_id) do
      team_projects = Map.get(state.projects, team_id, %{})
      {:reply, {:ok, Map.keys(team_projects)}, state}
    else
      {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:list_project_members, team_id, project_id}, _from, state) do
    team_projects = Map.get(state.projects, team_id, %{})

    case Map.fetch(team_projects, project_id) do
      {:ok, members} -> {:reply, {:ok, members}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:add_project_member_safe, team_id, project_id, user_id}, _from, state) do
    team_projects = Map.get(state.projects, team_id, %{})

    case Map.fetch(team_projects, project_id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, members} ->
        team_members = Map.get(state.teams, team_id, [])

        cond do
          user_id not in team_members ->
            {:reply, {:error, :not_team_member}, state}

          user_id in members ->
            {:reply, {:error, :conflict}, state}

          true ->
            new_projects = Map.put(team_projects, project_id, members ++ [user_id])
            {:reply, {:ok, user_id}, %{state | projects: Map.put(state.projects, team_id, new_projects)}}
        end
    end
  end

  defp put_project_member(state, team_id, project_id, user_id) do
    team_projects = Map.get(state.projects, team_id, %{})
    members = Map.get(team_projects, project_id, [])
    members = if user_id in members, do: members, else: members ++ [user_id]
    %{state | projects: Map.put(state.projects, team_id, Map.put(team_projects, project_id, members))}
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
  `Plug.Router` exposing two-level nested (team → project → member) resources
  with cascading authorization, protected by `AuthPlug`.
  """

  use Plug.Router, copy_opts_to_assign: :router_opts

  plug AuthPlug
  plug :match
  plug :dispatch

  get "/api/teams/:team_id/projects" do
    store = store(conn)
    actor = conn.assigns.current_user

    cond do
      not TeamStore.team_exists?(store, team_id) ->
        json(conn, 404, %{error: "not_found"})

      not TeamStore.is_member?(store, team_id, actor) ->
        json(conn, 403, %{error: "forbidden"})

      true ->
        {:ok, projects} = TeamStore.list_projects(store, team_id)
        json(conn, 200, %{projects: projects})
    end
  end

  get "/api/teams/:team_id/projects/:project_id/members" do
    store = store(conn)
    actor = conn.assigns.current_user

    case authorize(store, team_id, project_id, actor) do
      :ok ->
        {:ok, members} = TeamStore.list_project_members(store, team_id, project_id)
        json(conn, 200, %{members: members})

      {status, payload} ->
        json(conn, status, payload)
    end
  end

  post "/api/teams/:team_id/projects/:project_id/members" do
    store = store(conn)
    actor = conn.assigns.current_user

    case authorize(store, team_id, project_id, actor) do
      :ok ->
        add_project_member(conn, store, team_id, project_id)

      {status, payload} ->
        json(conn, status, payload)
    end
  end

  match _ do
    json(conn, 404, %{error: "not_found"})
  end

  # Cascading authorization for the acting user.
  defp authorize(store, team_id, project_id, actor) do
    cond do
      not TeamStore.team_exists?(store, team_id) ->
        {404, %{error: "not_found"}}

      not TeamStore.project_exists?(store, team_id, project_id) ->
        {404, %{error: "not_found"}}

      not TeamStore.is_member?(store, team_id, actor) ->
        {403, %{error: "forbidden"}}

      not TeamStore.is_project_member?(store, team_id, project_id, actor) ->
        {403, %{error: "forbidden"}}

      true ->
        :ok
    end
  end

  defp add_project_member(conn, store, team_id, project_id) do
    case read_user_id(conn) do
      {:ok, new_user_id, conn} ->
        case TeamStore.add_project_member_safe(store, team_id, project_id, new_user_id) do
          {:ok, uid} -> json(conn, 201, %{added: uid})
          {:error, :not_team_member} -> json(conn, 422, %{error: "not_a_team_member"})
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