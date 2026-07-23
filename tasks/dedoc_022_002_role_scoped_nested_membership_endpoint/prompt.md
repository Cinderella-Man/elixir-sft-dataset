# Add moduledoc, docs, and specs

Below: a correct, tested, undocumented module. Deliver the same module
fully documented — a `@moduledoc`, a per-public-function `@doc` and
`@spec`, and supporting `@type`s where useful. Behavior, names, structure:
unchanged. One file.

## The module

```elixir
defmodule TeamStore do
  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  def create_user(server, id, token), do: GenServer.call(server, {:create_user, id, token})

  def create_team(server, team_id), do: GenServer.call(server, {:create_team, team_id})

  def add_member(server, team_id, user_id, role),
    do: GenServer.call(server, {:add_member, team_id, user_id, role})

  def get_user_by_token(server, token), do: GenServer.call(server, {:get_user_by_token, token})

  def team_exists?(server, team_id), do: GenServer.call(server, {:team_exists?, team_id})

  def is_member?(server, team_id, user_id),
    do: GenServer.call(server, {:is_member?, team_id, user_id})

  def role_of(server, team_id, user_id),
    do: GenServer.call(server, {:role_of, team_id, user_id})

  def list_members(server, team_id), do: GenServer.call(server, {:list_members, team_id})

  def add_member_safe(server, team_id, user_id, role),
    do: GenServer.call(server, {:add_member_safe, team_id, user_id, role})

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
