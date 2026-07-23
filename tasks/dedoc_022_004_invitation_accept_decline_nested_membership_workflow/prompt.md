# Restore the documentation

The module below works and is fully tested — its behavior is final. What it
lost is every piece of documentation. Put it back:

- a `@moduledoc` covering purpose and usage,
- a `@doc` on each public function,
- a `@spec` on each public function (plus `@type`s where they clarify).

And keep your hands off the code itself: no renames, no refactors, no added
or removed functions, identical behavior everywhere. Return the whole
documented module in one file.

## The module

```elixir
defmodule TeamStore do
  use GenServer

  # ── Public API ──────────────────────────────────────────────────────────

  def start_link(opts) do
    {name, rest} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, rest, server_opts)
  end

  def create_user(server, id, token) do
    GenServer.call(server, {:create_user, id, token})
  end

  def create_team(server, team_id) do
    GenServer.call(server, {:create_team, team_id})
  end

  def add_member(server, team_id, user_id) do
    GenServer.call(server, {:add_member, team_id, user_id})
  end

  def get_user_by_token(server, token) do
    GenServer.call(server, {:get_user_by_token, token})
  end

  def team_exists?(server, team_id) do
    GenServer.call(server, {:team_exists?, team_id})
  end

  def is_member?(server, team_id, user_id) do
    GenServer.call(server, {:is_member?, team_id, user_id})
  end

  def is_invited?(server, team_id, user_id) do
    GenServer.call(server, {:is_invited?, team_id, user_id})
  end

  def list_members(server, team_id) do
    GenServer.call(server, {:list_members, team_id})
  end

  def list_invitations(server, team_id) do
    GenServer.call(server, {:list_invitations, team_id})
  end

  def invite_member(server, team_id, user_id) do
    GenServer.call(server, {:invite_member, team_id, user_id})
  end

  def accept_invite(server, team_id, user_id) do
    GenServer.call(server, {:accept_invite, team_id, user_id})
  end

  def decline_invite(server, team_id, user_id) do
    GenServer.call(server, {:decline_invite, team_id, user_id})
  end

  # ── GenServer callbacks ─────────────────────────────────────────────────

  @impl true
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
    team = Map.get(state.teams, team_id, new_team())
    {:reply, :ok, put_team(state, team_id, team)}
  end

  def handle_call({:add_member, team_id, user_id}, _from, state) do
    team = Map.get(state.teams, team_id, new_team())

    team = %{
      team
      | members: MapSet.put(team.members, user_id),
        invitations: MapSet.delete(team.invitations, user_id)
    }

    {:reply, :ok, put_team(state, team_id, team)}
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
    result =
      case Map.fetch(state.teams, team_id) do
        {:ok, team} -> MapSet.member?(team.members, user_id)
        :error -> false
      end

    {:reply, result, state}
  end

  def handle_call({:is_invited?, team_id, user_id}, _from, state) do
    result =
      case Map.fetch(state.teams, team_id) do
        {:ok, team} -> MapSet.member?(team.invitations, user_id)
        :error -> false
      end

    {:reply, result, state}
  end

  def handle_call({:list_members, team_id}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      {:ok, team} -> {:reply, {:ok, MapSet.to_list(team.members)}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:list_invitations, team_id}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      {:ok, team} -> {:reply, {:ok, MapSet.to_list(team.invitations)}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:invite_member, team_id, user_id}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, team} ->
        cond do
          MapSet.member?(team.members, user_id) ->
            {:reply, {:error, :conflict}, state}

          MapSet.member?(team.invitations, user_id) ->
            {:reply, {:error, :already_invited}, state}

          true ->
            team = %{team | invitations: MapSet.put(team.invitations, user_id)}
            {:reply, {:ok, user_id}, put_team(state, team_id, team)}
        end
    end
  end

  def handle_call({:accept_invite, team_id, user_id}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, team} ->
        if MapSet.member?(team.invitations, user_id) do
          team = %{
            team
            | invitations: MapSet.delete(team.invitations, user_id),
              members: MapSet.put(team.members, user_id)
          }

          {:reply, {:ok, user_id}, put_team(state, team_id, team)}
        else
          {:reply, {:error, :no_invitation}, state}
        end
    end
  end

  def handle_call({:decline_invite, team_id, user_id}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, team} ->
        if MapSet.member?(team.invitations, user_id) do
          team = %{team | invitations: MapSet.delete(team.invitations, user_id)}
          {:reply, {:ok, user_id}, put_team(state, team_id, team)}
        else
          {:reply, {:error, :no_invitation}, state}
        end
    end
  end

  # ── Internal helpers ────────────────────────────────────────────────────

  defp new_team do
    %{members: MapSet.new(), invitations: MapSet.new()}
  end

  defp put_team(state, team_id, team) do
    %{state | teams: Map.put(state.teams, team_id, team)}
  end
end

defmodule AuthPlug do
  import Plug.Conn

  @behaviour Plug

  def init(opts), do: opts

  def call(conn, opts) do
    store =
      Map.get(conn.private, :team_store) ||
        Keyword.get(opts, :store, TeamStore)

    with [header] <- get_req_header(conn, "authorization"),
         "Bearer " <> token <- header,
         {:ok, user_id} <- TeamStore.get_user_by_token(store, token) do
      assign(conn, :current_user, user_id)
    else
      _ -> unauthorized(conn)
    end
  end

  defp unauthorized(conn) do
    body = Jason.encode!(%{error: "unauthorized"})

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, body)
    |> halt()
  end
end

defmodule TeamRouter do
  use Plug.Router

  # AuthPlug runs BEFORE :match — every request is authenticated before any
  # route matching happens (including the `match _` catch-all).
  plug(AuthPlug, store: Application.compile_env(:team_app, :store, TeamStore))

  plug(:match)

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason
  )

  plug(:dispatch)

  def init(opts), do: super(opts)

  def call(conn, opts) do
    store = Map.get(conn.private, :team_store) || Keyword.get(opts, :store, TeamStore)
    conn = put_private(conn, :team_store, store)
    super(conn, opts)
  end

  get "/api/teams/:team_id/members" do
    store = store(conn)

    with_team_and_member(conn, store, team_id, fn ->
      {:ok, members} = TeamStore.list_members(store, team_id)
      send_json(conn, 200, %{members: members})
    end)
  end

  get "/api/teams/:team_id/invitations" do
    store = store(conn)

    with_team_and_member(conn, store, team_id, fn ->
      {:ok, invitations} = TeamStore.list_invitations(store, team_id)
      send_json(conn, 200, %{invitations: invitations})
    end)
  end

  post "/api/teams/:team_id/invitations" do
    store = store(conn)
    current = conn.assigns.current_user

    cond do
      not TeamStore.team_exists?(store, team_id) ->
        send_json(conn, 404, %{error: "not_found"})

      not TeamStore.is_member?(store, team_id, current) ->
        send_json(conn, 403, %{error: "forbidden"})

      true ->
        handle_invite(conn, store, team_id)
    end
  end

  post "/api/teams/:team_id/invitations/:user_id/accept" do
    store = store(conn)

    with_own_invitation(conn, store, team_id, user_id, fn ->
      case TeamStore.accept_invite(store, team_id, user_id) do
        {:ok, id} -> send_json(conn, 200, %{accepted: id})
        {:error, :no_invitation} -> send_json(conn, 409, %{error: "no_invitation"})
      end
    end)
  end

  post "/api/teams/:team_id/invitations/:user_id/decline" do
    store = store(conn)

    with_own_invitation(conn, store, team_id, user_id, fn ->
      case TeamStore.decline_invite(store, team_id, user_id) do
        {:ok, id} -> send_json(conn, 200, %{declined: id})
        {:error, :no_invitation} -> send_json(conn, 409, %{error: "no_invitation"})
      end
    end)
  end

  match _ do
    send_json(conn, 404, %{error: "not_found"})
  end

  # ── Internal helpers ────────────────────────────────────────────────────

  defp store(conn), do: Map.get(conn.private, :team_store, TeamStore)

  defp with_team_and_member(conn, store, team_id, fun) do
    current = conn.assigns.current_user

    cond do
      not TeamStore.team_exists?(store, team_id) ->
        send_json(conn, 404, %{error: "not_found"})

      not TeamStore.is_member?(store, team_id, current) ->
        send_json(conn, 403, %{error: "forbidden"})

      true ->
        fun.()
    end
  end

  defp with_own_invitation(conn, store, team_id, user_id, fun) do
    current = conn.assigns.current_user

    cond do
      not TeamStore.team_exists?(store, team_id) ->
        send_json(conn, 404, %{error: "not_found"})

      current != user_id ->
        send_json(conn, 403, %{error: "forbidden"})

      true ->
        fun.()
    end
  end

  defp handle_invite(conn, store, team_id) do
    case conn.body_params do
      %{"user_id" => user_id} when is_binary(user_id) ->
        case TeamStore.invite_member(store, team_id, user_id) do
          {:ok, id} -> send_json(conn, 201, %{invited: id})
          {:error, :conflict} -> send_json(conn, 409, %{error: "conflict"})
          {:error, :already_invited} -> send_json(conn, 409, %{error: "already_invited"})
          {:error, :not_found} -> send_json(conn, 404, %{error: "not_found"})
        end

      _ ->
        send_json(conn, 400, %{error: "bad_request"})
    end
  end

  defp send_json(conn, status, payload) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(payload))
  end
end
```
