defmodule TeamStore do
  @moduledoc """
  In-memory `GenServer` holding users, teams, memberships and pending
  invitations. Joining a team is a two-step lifecycle: `invite/3` records a
  pending invitation and `accept_invitation/3` promotes it to membership.
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

  def get_user_by_token(server, token), do: GenServer.call(server, {:get_user_by_token, token})

  def team_exists?(server, team_id), do: GenServer.call(server, {:team_exists?, team_id})

  def is_member?(server, team_id, user_id),
    do: GenServer.call(server, {:is_member?, team_id, user_id})

  def list_members(server, team_id), do: GenServer.call(server, {:list_members, team_id})

  def list_invitations(server, team_id), do: GenServer.call(server, {:list_invitations, team_id})

  def has_pending_invite?(server, team_id, user_id),
    do: GenServer.call(server, {:has_pending_invite?, team_id, user_id})

  def invite(server, team_id, user_id),
    do: GenServer.call(server, {:invite, team_id, user_id})

  def accept_invitation(server, team_id, user_id),
    do: GenServer.call(server, {:accept_invitation, team_id, user_id})

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    {:ok, %{tokens: %{}, teams: %{}, invites: %{}}}
  end

  @impl true
  def handle_call({:create_user, id, token}, _from, state) do
    {:reply, :ok, put_in(state.tokens[token], id)}
  end

  def handle_call({:create_team, team_id}, _from, state) do
    teams = Map.put_new(state.teams, team_id, [])
    invites = Map.put_new(state.invites, team_id, [])
    {:reply, :ok, %{state | teams: teams, invites: invites}}
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

  def handle_call({:list_invitations, team_id}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      {:ok, _} -> {:reply, {:ok, Map.get(state.invites, team_id, [])}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:has_pending_invite?, team_id, user_id}, _from, state) do
    {:reply, user_id in Map.get(state.invites, team_id, []), state}
  end

  def handle_call({:invite, team_id, user_id}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, members} ->
        pending = Map.get(state.invites, team_id, [])

        cond do
          user_id in members ->
            {:reply, {:error, :conflict}, state}

          user_id in pending ->
            {:reply, {:error, :conflict}, state}

          true ->
            invites = Map.put(state.invites, team_id, pending ++ [user_id])
            {:reply, {:ok, user_id}, %{state | invites: invites}}
        end
    end
  end

  def handle_call({:accept_invitation, team_id, user_id}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, members} ->
        pending = Map.get(state.invites, team_id, [])

        if user_id in pending do
          new_pending = List.delete(pending, user_id)
          new_members = if user_id in members, do: members, else: members ++ [user_id]

          state = %{
            state
            | invites: Map.put(state.invites, team_id, new_pending),
              teams: Map.put(state.teams, team_id, new_members)
          }

          {:reply, {:ok, user_id}, state}
        else
          {:reply, {:error, :not_found}, state}
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
  `Plug.Router` exposing invitation-based nested team-membership resources,
  protected by `AuthPlug`.
  """

  use Plug.Router, copy_opts_to_assign: :router_opts

  plug AuthPlug
  plug :match
  plug :dispatch

  get "/api/teams/:team_id/members" do
    store = store(conn)
    actor = conn.assigns.current_user

    cond do
      not TeamStore.team_exists?(store, team_id) ->
        json(conn, 404, %{error: "not_found"})

      not TeamStore.is_member?(store, team_id, actor) ->
        json(conn, 403, %{error: "forbidden"})

      true ->
        {:ok, members} = TeamStore.list_members(store, team_id)
        json(conn, 200, %{members: members})
    end
  end

  get "/api/teams/:team_id/invitations" do
    store = store(conn)
    actor = conn.assigns.current_user

    cond do
      not TeamStore.team_exists?(store, team_id) ->
        json(conn, 404, %{error: "not_found"})

      not TeamStore.is_member?(store, team_id, actor) ->
        json(conn, 403, %{error: "forbidden"})

      true ->
        {:ok, pending} = TeamStore.list_invitations(store, team_id)
        json(conn, 200, %{invitations: pending})
    end
  end

  post "/api/teams/:team_id/invitations/:user_id/accept" do
    store = store(conn)
    actor = conn.assigns.current_user

    cond do
      not TeamStore.team_exists?(store, team_id) ->
        json(conn, 404, %{error: "not_found"})

      actor != user_id ->
        json(conn, 403, %{error: "forbidden"})

      true ->
        case TeamStore.accept_invitation(store, team_id, user_id) do
          {:ok, uid} -> json(conn, 200, %{joined: uid})
          {:error, :not_found} -> json(conn, 404, %{error: "not_found"})
        end
    end
  end

  post "/api/teams/:team_id/invitations" do
    store = store(conn)
    actor = conn.assigns.current_user

    cond do
      not TeamStore.team_exists?(store, team_id) ->
        json(conn, 404, %{error: "not_found"})

      not TeamStore.is_member?(store, team_id, actor) ->
        json(conn, 403, %{error: "forbidden"})

      true ->
        create_invite(conn, store, team_id)
    end
  end

  match _ do
    json(conn, 404, %{error: "not_found"})
  end

  defp create_invite(conn, store, team_id) do
    case read_user_id(conn) do
      {:ok, invited_id, conn} ->
        case TeamStore.invite(store, team_id, invited_id) do
          {:ok, uid} -> json(conn, 201, %{invited: uid, status: "pending"})
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