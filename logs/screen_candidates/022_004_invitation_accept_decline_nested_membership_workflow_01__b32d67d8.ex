defmodule TeamStore do
  @moduledoc """
  In-memory state store for users, teams, active memberships and pending
  invitations.

  The store is a `GenServer` holding a single map-based state:

    * `:users` — map of bearer token to user id
    * `:teams` — map of team id to a map with `:members` (a `MapSet` of active
      member ids) and `:invitations` (a `MapSet` of pending invited user ids)

  Membership follows an invitation / RSVP workflow: an existing member invites a
  user (creating a *pending* invitation), and the invited user must accept it to
  become an *active* member, or decline it to drop the invitation.
  """

  use GenServer

  @type server :: GenServer.server()
  @type user_id :: String.t()
  @type team_id :: String.t()

  # ----------------------------------------------------------------------------
  # Client API
  # ----------------------------------------------------------------------------

  @doc """
  Starts the store.

  Accepts the usual `GenServer` options; in particular `:name` to register the
  process under a name.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, _rest} = Keyword.pop(opts, :name)

    case name do
      nil -> GenServer.start_link(__MODULE__, :ok, [])
      name -> GenServer.start_link(__MODULE__, :ok, name: name)
    end
  end

  @doc """
  Stores a user with the given `id` and bearer `token`.
  """
  @spec create_user(server(), user_id(), String.t()) :: :ok
  def create_user(server, id, token) do
    GenServer.call(server, {:create_user, id, token})
  end

  @doc """
  Creates a team with no members and no pending invitations.
  """
  @spec create_team(server(), team_id()) :: :ok
  def create_team(server, team_id) do
    GenServer.call(server, {:create_team, team_id})
  end

  @doc """
  Adds `user_id` directly as an active member of `team_id`, bypassing the
  invitation workflow. Intended for seeding.
  """
  @spec add_member(server(), team_id(), user_id()) :: :ok
  def add_member(server, team_id, user_id) do
    GenServer.call(server, {:add_member, team_id, user_id})
  end

  @doc """
  Looks up a user id by bearer `token`.

  Returns `{:ok, user_id}` or `:error`.
  """
  @spec get_user_by_token(server(), String.t()) :: {:ok, user_id()} | :error
  def get_user_by_token(server, token) do
    GenServer.call(server, {:get_user_by_token, token})
  end

  @doc """
  Returns `true` when the team exists.
  """
  @spec team_exists?(server(), team_id()) :: boolean()
  def team_exists?(server, team_id) do
    GenServer.call(server, {:team_exists?, team_id})
  end

  @doc """
  Returns `true` when `user_id` is an *active* member of `team_id`.
  """
  @spec is_member?(server(), team_id(), user_id()) :: boolean()
  def is_member?(server, team_id, user_id) do
    GenServer.call(server, {:is_member?, team_id, user_id})
  end

  @doc """
  Returns `true` when `user_id` has a *pending* invitation for `team_id`.
  """
  @spec is_invited?(server(), team_id(), user_id()) :: boolean()
  def is_invited?(server, team_id, user_id) do
    GenServer.call(server, {:is_invited?, team_id, user_id})
  end

  @doc """
  Lists the active member ids of `team_id`.

  Returns `{:ok, members}` or `{:error, :not_found}` when the team is unknown.
  """
  @spec list_members(server(), team_id()) :: {:ok, [user_id()]} | {:error, :not_found}
  def list_members(server, team_id) do
    GenServer.call(server, {:list_members, team_id})
  end

  @doc """
  Lists the pending invited user ids of `team_id`.

  Returns `{:ok, invitations}` or `{:error, :not_found}` when the team is unknown.
  """
  @spec list_invitations(server(), team_id()) :: {:ok, [user_id()]} | {:error, :not_found}
  def list_invitations(server, team_id) do
    GenServer.call(server, {:list_invitations, team_id})
  end

  @doc """
  Creates a pending invitation for `user_id` on `team_id`.

  Returns `{:ok, user_id}` on success, `{:error, :not_found}` when the team does
  not exist, `{:error, :conflict}` when the user is already an active member and
  `{:error, :already_invited}` when a pending invitation already exists.
  """
  @spec invite_member(server(), team_id(), user_id()) ::
          {:ok, user_id()} | {:error, :not_found | :conflict | :already_invited}
  def invite_member(server, team_id, user_id) do
    GenServer.call(server, {:invite_member, team_id, user_id})
  end

  @doc """
  Accepts a pending invitation: removes the invitation and adds the user as an
  active member.

  Returns `{:ok, user_id}` on success, `{:error, :not_found}` when the team does
  not exist and `{:error, :no_invitation}` when there is no pending invitation.
  """
  @spec accept_invite(server(), team_id(), user_id()) ::
          {:ok, user_id()} | {:error, :not_found | :no_invitation}
  def accept_invite(server, team_id, user_id) do
    GenServer.call(server, {:accept_invite, team_id, user_id})
  end

  @doc """
  Declines a pending invitation: removes the invitation *without* adding the user
  as a member.

  Returns `{:ok, user_id}` on success, `{:error, :not_found}` when the team does
  not exist and `{:error, :no_invitation}` when there is no pending invitation.
  """
  @spec decline_invite(server(), team_id(), user_id()) ::
          {:ok, user_id()} | {:error, :not_found | :no_invitation}
  def decline_invite(server, team_id, user_id) do
    GenServer.call(server, {:decline_invite, team_id, user_id})
  end

  # ----------------------------------------------------------------------------
  # Server callbacks
  # ----------------------------------------------------------------------------

  @impl GenServer
  def init(:ok) do
    {:ok, %{users: %{}, teams: %{}}}
  end

  @impl GenServer
  def handle_call({:create_user, id, token}, _from, state) do
    {:reply, :ok, put_in(state.users[token], id)}
  end

  def handle_call({:create_team, team_id}, _from, state) do
    team = %{members: MapSet.new(), invitations: MapSet.new()}
    {:reply, :ok, put_in(state.teams[team_id], team)}
  end

  def handle_call({:add_member, team_id, user_id}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      {:ok, team} ->
        team = %{team | members: MapSet.put(team.members, user_id)}
        {:reply, :ok, put_in(state.teams[team_id], team)}

      :error ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:get_user_by_token, token}, _from, state) do
    {:reply, Map.fetch(state.users, token), state}
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
    result =
      case Map.fetch(state.teams, team_id) do
        {:ok, team} -> {:ok, Enum.sort(MapSet.to_list(team.members))}
        :error -> {:error, :not_found}
      end

    {:reply, result, state}
  end

  def handle_call({:list_invitations, team_id}, _from, state) do
    result =
      case Map.fetch(state.teams, team_id) do
        {:ok, team} -> {:ok, Enum.sort(MapSet.to_list(team.invitations))}
        :error -> {:error, :not_found}
      end

    {:reply, result, state}
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
            {:reply, {:ok, user_id}, put_in(state.teams[team_id], team)}
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

          {:reply, {:ok, user_id}, put_in(state.teams[team_id], team)}
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
          {:reply, {:ok, user_id}, put_in(state.teams[team_id], team)}
        else
          {:reply, {:error, :no_invitation}, state}
        end
    end
  end
end

defmodule AuthPlug do
  @moduledoc """
  Bearer-token authentication plug.

  Reads the `authorization` request header, expects a `Bearer <token>` value and
  resolves it to a user id through `TeamStore.get_user_by_token/2`. On success the
  user id is stored in `conn.assigns[:current_user]`; otherwise the connection is
  halted with a `401` JSON body `{"error": "unauthorized"}`.

  Authentication only proves the token maps to a known user — it says nothing
  about team membership, which is enforced per-route.
  """

  import Plug.Conn

  @behaviour Plug

  @doc """
  Initializes the plug.

  Expects a `:store` option identifying the `TeamStore` process to query.
  """
  @impl Plug
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @doc """
  Authenticates the connection, assigning `:current_user` or halting with `401`.
  """
  @impl Plug
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    store = Keyword.fetch!(opts, :store)

    with [header] <- get_req_header(conn, "authorization"),
         {:ok, token} <- parse_bearer(header),
         {:ok, user_id} <- TeamStore.get_user_by_token(store, token) do
      assign(conn, :current_user, user_id)
    else
      _other -> unauthorized(conn)
    end
  end

  @spec parse_bearer(String.t()) :: {:ok, String.t()} | :error
  defp parse_bearer("Bearer " <> token) do
    case String.trim(token) do
      "" -> :error
      token -> {:ok, token}
    end
  end

  defp parse_bearer(_other), do: :error

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
  `Plug.Router` exposing the nested team-membership endpoints built around an
  invitation / RSVP workflow.

  Routes:

    * `GET  /api/teams/:team_id/members`
    * `GET  /api/teams/:team_id/invitations`
    * `POST /api/teams/:team_id/invitations`
    * `POST /api/teams/:team_id/invitations/:user_id/accept`
    * `POST /api/teams/:team_id/invitations/:user_id/decline`

  The router requires a `:store` option naming the `TeamStore` process. All
  responses are JSON. Checks are applied in a fixed order: team existence first,
  then authorization, then operation-specific outcomes.
  """

  use Plug.Router

  plug(:match)

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason
  )

  plug(:auth)
  plug(:dispatch, builder_opts())

  @doc """
  Initializes the router options.
  """
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec auth(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  defp auth(conn, _opts) do
    store = store!(conn.private[:plug_route_opts] || [])
    AuthPlug.call(conn, AuthPlug.init(store: store))
  end

  get "/api/teams/:team_id/members" do
    store = store!(opts)
    user = conn.assigns.current_user

    with :ok <- ensure_team(store, team_id),
         :ok <- ensure_member(store, team_id, user),
         {:ok, members} <- TeamStore.list_members(store, team_id) do
      send_json(conn, 200, %{members: members})
    else
      {:error, reason} -> send_error(conn, reason)
    end
  end

  get "/api/teams/:team_id/invitations" do
    store = store!(opts)
    user = conn.assigns.current_user

    with :ok <- ensure_team(store, team_id),
         :ok <- ensure_member(store, team_id, user),
         {:ok, invitations} <- TeamStore.list_invitations(store, team_id) do
      send_json(conn, 200, %{invitations: invitations})
    else
      {:error, reason} -> send_error(conn, reason)
    end
  end

  post "/api/teams/:team_id/invitations" do
    store = store!(opts)
    user = conn.assigns.current_user

    with :ok <- ensure_team(store, team_id),
         :ok <- ensure_member(store, team_id, user),
         {:ok, invitee} <- fetch_user_id(conn.body_params),
         {:ok, invited} <- TeamStore.invite_member(store, team_id, invitee) do
      send_json(conn, 201, %{invited: invited})
    else
      {:error, reason} -> send_error(conn, reason)
    end
  end

  post "/api/teams/:team_id/invitations/:user_id/accept" do
    store = store!(opts)
    current = conn.assigns.current_user

    with :ok <- ensure_team(store, team_id),
         :ok <- ensure_self(current, user_id),
         {:ok, accepted} <- TeamStore.accept_invite(store, team_id, user_id) do
      send_json(conn, 200, %{accepted: accepted})
    else
      {:error, reason} -> send_error(conn, reason)
    end
  end

  post "/api/teams/:team_id/invitations/:user_id/decline" do
    store = store!(opts)
    current = conn.assigns.current_user

    with :ok <- ensure_team(store, team_id),
         :ok <- ensure_self(current, user_id),
         {:ok, declined} <- TeamStore.decline_invite(store, team_id, user_id) do
      send_json(conn, 200, %{declined: declined})
    else
      {:error, reason} -> send_error(conn, reason)
    end
  end

  match _ do
    send_error(conn, :not_found)
  end

  # ----------------------------------------------------------------------------
  # Helpers
  # ----------------------------------------------------------------------------

  @spec store!(keyword() | map()) :: GenServer.server()
  defp store!(opts) when is_list(opts), do: Keyword.fetch!(opts, :store)
  defp store!(%{store: store}), do: store

  @spec ensure_team(GenServer.server(), String.t()) :: :ok | {:error, :not_found}
  defp ensure_team(store, team_id) do
    if TeamStore.team_exists?(store, team_id), do: :ok, else: {:error, :not_found}
  end

  @spec ensure_member(GenServer.server(), String.t(), String.t()) :: :ok | {:error, :forbidden}
  defp ensure_member(store, team_id, user_id) do
    if TeamStore.is_member?(store, team_id, user_id), do: :ok, else: {:error, :forbidden}
  end

  @spec ensure_self(String.t(), String.t()) :: :ok | {:error, :forbidden}
  defp ensure_self(current_user, user_id) do
    if current_user == user_id, do: :ok, else: {:error, :forbidden}
  end

  @spec fetch_user_id(map() | term()) :: {:ok, String.t()} | {:error, :bad_request}
  defp fetch_user_id(%{"user_id" => user_id}) when is_binary(user_id) and user_id != "" do
    {:ok, user_id}
  end

  defp fetch_user_id(_params), do: {:error, :bad_request}

  @spec send_error(Plug.Conn.t(), atom()) :: Plug.Conn.t()
  defp send_error(conn, reason) do
    send_json(conn, status_for(reason), %{error: Atom.to_string(reason)})
  end

  @spec status_for(atom()) :: pos_integer()
  defp status_for(:not_found), do: 404
  defp status_for(:forbidden), do: 403
  defp status_for(:bad_request), do: 400
  defp status_for(:conflict), do: 409
  defp status_for(:already_invited), do: 409
  defp status_for(:no_invitation), do: 409
  defp status_for(_other), do: 500

  @spec send_json(Plug.Conn.t(), pos_integer(), map()) :: Plug.Conn.t()
  defp send_json(conn, status, payload) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(payload))
  end
end