defmodule TeamStore do
  @moduledoc """
  In-memory state store for invitation-gated team membership.

  Holds all application state — users (keyed by id), tokens (mapping
  bearer token to user id), and teams. Each team tracks its active
  members, its pending invitations, and its capacity (the maximum number
  of active members allowed).

  Membership is a two-step handshake: an active member invites a user,
  creating a pending invitation; the invited user later accepts, which
  promotes them to an active member if the team has spare capacity.
  """

  use GenServer

  @typedoc "Opaque server reference (pid or registered name)."
  @type server :: GenServer.server()

  # ----------------------------------------------------------------------
  # Client API
  # ----------------------------------------------------------------------

  @doc """
  Starts the store process.

  Accepts a `:name` option used to register the process.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc "Stores a user with the given `id` and bearer `token`."
  @spec create_user(server(), String.t(), String.t()) :: :ok
  def create_user(server, id, token) do
    GenServer.call(server, {:create_user, id, token})
  end

  @doc "Creates a team with an empty member list and the given `capacity`."
  @spec create_team(server(), String.t(), integer()) :: :ok
  def create_team(server, team_id, capacity) do
    GenServer.call(server, {:create_team, team_id, capacity})
  end

  @doc "Directly adds `user_id` to the team's active members (ignores capacity)."
  @spec add_member(server(), String.t(), String.t()) :: :ok
  def add_member(server, team_id, user_id) do
    GenServer.call(server, {:add_member, team_id, user_id})
  end

  @doc "Looks up a user id by bearer `token`."
  @spec get_user_by_token(server(), String.t()) :: {:ok, String.t()} | :error
  def get_user_by_token(server, token) do
    GenServer.call(server, {:get_user_by_token, token})
  end

  @doc "Returns whether a team with `team_id` exists."
  @spec team_exists?(server(), String.t()) :: boolean()
  def team_exists?(server, team_id) do
    GenServer.call(server, {:team_exists?, team_id})
  end

  @doc "Returns whether `user_id` is an active member of the team."
  @spec is_member?(server(), String.t(), String.t()) :: boolean()
  def is_member?(server, team_id, user_id) do
    GenServer.call(server, {:is_member?, team_id, user_id})
  end

  @doc "Returns whether `user_id` has a pending invitation on the team."
  @spec has_invitation?(server(), String.t(), String.t()) :: boolean()
  def has_invitation?(server, team_id, user_id) do
    GenServer.call(server, {:has_invitation?, team_id, user_id})
  end

  @doc "Lists the active member ids of the team."
  @spec list_members(server(), String.t()) :: {:ok, [String.t()]} | {:error, :not_found}
  def list_members(server, team_id) do
    GenServer.call(server, {:list_members, team_id})
  end

  @doc "Lists the pending invitation user ids of the team."
  @spec list_invitations(server(), String.t()) :: {:ok, [String.t()]} | {:error, :not_found}
  def list_invitations(server, team_id) do
    GenServer.call(server, {:list_invitations, team_id})
  end

  @doc """
  Records a pending invitation for `user_id` on the team.

  Returns `{:error, :not_found}` if the team is missing,
  `{:error, :already_member}` if the user is already active,
  `{:error, :already_invited}` if the user is already invited,
  otherwise `{:ok, user_id}`.
  """
  @spec invite(server(), String.t(), String.t()) ::
          {:ok, String.t()}
          | {:error, :not_found | :already_member | :already_invited}
  def invite(server, team_id, user_id) do
    GenServer.call(server, {:invite, team_id, user_id})
  end

  @doc """
  Promotes `user_id`'s own pending invitation to active membership.

  Returns `{:error, :not_found}` if the team is missing,
  `{:error, :no_invitation}` if the user has no pending invitation,
  `{:error, :team_full}` if the team is at capacity,
  otherwise `{:ok, team_id}`.
  """
  @spec accept(server(), String.t(), String.t()) ::
          {:ok, String.t()}
          | {:error, :not_found | :no_invitation | :team_full}
  def accept(server, team_id, user_id) do
    GenServer.call(server, {:accept, team_id, user_id})
  end

  # ----------------------------------------------------------------------
  # Server callbacks
  # ----------------------------------------------------------------------

  @impl true
  @spec init(keyword()) :: {:ok, map()}
  def init(_opts) do
    {:ok, %{users: %{}, tokens: %{}, teams: %{}}}
  end

  @impl true
  def handle_call({:create_user, id, token}, _from, state) do
    state =
      state
      |> put_in([:users, id], %{id: id, token: token})
      |> put_in([:tokens, token], id)

    {:reply, :ok, state}
  end

  def handle_call({:create_team, team_id, capacity}, _from, state) do
    team = %{members: [], invitations: [], capacity: capacity}
    {:reply, :ok, put_in(state, [:teams, team_id], team)}
  end

  def handle_call({:add_member, team_id, user_id}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      {:ok, team} ->
        team = %{team | members: add_unique(team.members, user_id)}
        {:reply, :ok, put_in(state, [:teams, team_id], team)}

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
    result =
      case Map.fetch(state.teams, team_id) do
        {:ok, team} -> user_id in team.members
        :error -> false
      end

    {:reply, result, state}
  end

  def handle_call({:has_invitation?, team_id, user_id}, _from, state) do
    result =
      case Map.fetch(state.teams, team_id) do
        {:ok, team} -> user_id in team.invitations
        :error -> false
      end

    {:reply, result, state}
  end

  def handle_call({:list_members, team_id}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      {:ok, team} -> {:reply, {:ok, team.members}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:list_invitations, team_id}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      {:ok, team} -> {:reply, {:ok, team.invitations}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:invite, team_id, user_id}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, team} ->
        cond do
          user_id in team.members ->
            {:reply, {:error, :already_member}, state}

          user_id in team.invitations ->
            {:reply, {:error, :already_invited}, state}

          true ->
            team = %{team | invitations: team.invitations ++ [user_id]}
            {:reply, {:ok, user_id}, put_in(state, [:teams, team_id], team)}
        end
    end
  end

  def handle_call({:accept, team_id, user_id}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, team} ->
        cond do
          user_id not in team.invitations ->
            {:reply, {:error, :no_invitation}, state}

          length(team.members) >= team.capacity ->
            {:reply, {:error, :team_full}, state}

          true ->
            team = %{
              team
              | invitations: List.delete(team.invitations, user_id),
                members: add_unique(team.members, user_id)
            }

            {:reply, {:ok, team_id}, put_in(state, [:teams, team_id], team)}
        end
    end
  end

  @spec add_unique([String.t()], String.t()) :: [String.t()]
  defp add_unique(list, value) do
    if value in list, do: list, else: list ++ [value]
  end
end

defmodule AuthPlug do
  @moduledoc """
  Bearer-token authentication plug.

  Reads the `authorization` header, expects a value of the form
  `Bearer <token>`, and resolves the token to a user id via
  `TeamStore.get_user_by_token/2`. On success the user id is assigned to
  the conn as `:current_user`. On a missing or invalid token the conn is
  halted with a `401` JSON response `{"error": "unauthorized"}`.
  """

  import Plug.Conn

  @behaviour Plug

  @doc "Initializes the plug, capturing the `:store` option."
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @doc "Authenticates the request, assigning `:current_user` or halting with 401."
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    store = Keyword.fetch!(opts, :store)

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

  @spec unauthorized(Plug.Conn.t()) :: Plug.Conn.t()
  defp unauthorized(conn) do
    body = Jason.encode!(%{error: "unauthorized"})

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, body)
    |> halt()
  end
end

defmodule TeamRouter do
  @moduledoc """
  Plug router for invitation-gated nested team-membership endpoints.

  Requires a `:store` option identifying the `TeamStore` process. All
  requests are authenticated by `AuthPlug` before routing.

  Endpoints:

    * `GET /api/teams/:team_id/members` — list active members (member-only).
    * `GET /api/teams/:team_id/invitations` — list pending invitations
      (member-only).
    * `POST /api/teams/:team_id/invitations` — invite a user (member-only).
    * `POST /api/teams/:team_id/members` — accept one's own invitation.

  All responses use the `application/json` content type.
  """

  use Plug.Router

  @doc "Invokes the router, injecting the `:store` process for later use."
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    conn = put_private(conn, :team_store, Keyword.fetch!(opts, :store))
    super(conn, opts)
  end

  plug(:match)

  plug(AuthPlug, builder_opts())

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason
  )

  plug(:dispatch)

  get "/api/teams/:team_id/members" do
    store = store(conn)
    user = conn.assigns.current_user

    cond do
      not TeamStore.team_exists?(store, team_id) ->
        send_json(conn, 404, %{error: "not_found"})

      not TeamStore.is_member?(store, team_id, user) ->
        send_json(conn, 403, %{error: "forbidden"})

      true ->
        {:ok, members} = TeamStore.list_members(store, team_id)
        send_json(conn, 200, %{members: members})
    end
  end

  get "/api/teams/:team_id/invitations" do
    store = store(conn)
    user = conn.assigns.current_user

    cond do
      not TeamStore.team_exists?(store, team_id) ->
        send_json(conn, 404, %{error: "not_found"})

      not TeamStore.is_member?(store, team_id, user) ->
        send_json(conn, 403, %{error: "forbidden"})

      true ->
        {:ok, invitations} = TeamStore.list_invitations(store, team_id)
        send_json(conn, 200, %{invitations: invitations})
    end
  end

  post "/api/teams/:team_id/invitations" do
    store = store(conn)
    user = conn.assigns.current_user

    cond do
      not TeamStore.team_exists?(store, team_id) ->
        send_json(conn, 404, %{error: "not_found"})

      not TeamStore.is_member?(store, team_id, user) ->
        send_json(conn, 403, %{error: "forbidden"})

      true ->
        handle_invite(conn, store, team_id)
    end
  end

  post "/api/teams/:team_id/members" do
    store = store(conn)
    user = conn.assigns.current_user

    if TeamStore.team_exists?(store, team_id) do
      handle_accept(conn, store, team_id, user)
    else
      send_json(conn, 404, %{error: "not_found"})
    end
  end

  match _ do
    send_json(conn, 404, %{error: "not_found"})
  end

  @spec handle_invite(Plug.Conn.t(), TeamStore.server(), String.t()) :: Plug.Conn.t()
  defp handle_invite(conn, store, team_id) do
    case conn.body_params do
      %{"user_id" => user_id} when is_binary(user_id) ->
        case TeamStore.invite(store, team_id, user_id) do
          {:ok, invited} -> send_json(conn, 201, %{invited: invited})
          {:error, :already_member} -> send_json(conn, 409, %{error: "already_member"})
          {:error, :already_invited} -> send_json(conn, 409, %{error: "already_invited"})
          {:error, :not_found} -> send_json(conn, 404, %{error: "not_found"})
        end

      _ ->
        send_json(conn, 400, %{error: "bad_request"})
    end
  end

  @spec handle_accept(Plug.Conn.t(), TeamStore.server(), String.t(), String.t()) ::
          Plug.Conn.t()
  defp handle_accept(conn, store, team_id, user) do
    case TeamStore.accept(store, team_id, user) do
      {:ok, joined} -> send_json(conn, 201, %{joined: joined})
      {:error, :no_invitation} -> send_json(conn, 403, %{error: "forbidden"})
      {:error, :team_full} -> send_json(conn, 409, %{error: "team_full"})
      {:error, :not_found} -> send_json(conn, 404, %{error: "not_found"})
    end
  end

  @spec store(Plug.Conn.t()) :: TeamStore.server()
  defp store(conn), do: conn.private.team_store

  @spec send_json(Plug.Conn.t(), non_neg_integer(), map()) :: Plug.Conn.t()
  defp send_json(conn, status, payload) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(payload))
  end
end
