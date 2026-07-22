defmodule TeamStore do
  @moduledoc """
  In-memory store for users, teams and role-tagged team memberships.

  State is held entirely in the GenServer process:

    * `users` — a map of `user_id => token`
    * `tokens` — a reverse index of `token => user_id`
    * `teams` — a `MapSet` of known team identifiers
    * `memberships` — a map of `team_id => %{user_id => role}`

  Roles are the binaries `"owner"`, `"admin"` and `"member"`.
  """

  use GenServer

  @typedoc "A user identifier."
  @type user_id :: String.t()

  @typedoc "A team identifier."
  @type team_id :: String.t()

  @typedoc "A membership role."
  @type role :: String.t()

  @valid_roles ["owner", "admin", "member"]

  defstruct users: %{}, tokens: %{}, teams: MapSet.new(), memberships: %{}

  @doc """
  Returns the list of valid membership roles.
  """
  @spec valid_roles() :: [role()]
  def valid_roles, do: @valid_roles

  @doc """
  Returns `true` when `role` is one of the valid membership roles.
  """
  @spec valid_role?(term()) :: boolean()
  def valid_role?(role), do: role in @valid_roles

  @doc """
  Starts the store process.

  Accepts the standard `GenServer` options, notably `:name`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, _rest} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, :ok, server_opts)
  end

  @doc """
  Stores a user together with the bearer token used to authenticate it.
  """
  @spec create_user(GenServer.server(), user_id(), String.t()) :: :ok
  def create_user(server, id, token) do
    GenServer.call(server, {:create_user, id, token})
  end

  @doc """
  Creates a team. Creating an existing team is a no-op.
  """
  @spec create_team(GenServer.server(), team_id()) :: :ok
  def create_team(server, team_id) do
    GenServer.call(server, {:create_team, team_id})
  end

  @doc """
  Seeds a membership with the given role, without any validation.
  """
  @spec add_member(GenServer.server(), team_id(), user_id(), role()) :: :ok
  def add_member(server, team_id, user_id, role) do
    GenServer.call(server, {:add_member, team_id, user_id, role})
  end

  @doc """
  Looks a user up by bearer token.

  Returns `{:ok, user_id}` or `:error`.
  """
  @spec get_user_by_token(GenServer.server(), String.t()) :: {:ok, user_id()} | :error
  def get_user_by_token(server, token) do
    GenServer.call(server, {:get_user_by_token, token})
  end

  @doc """
  Returns `true` when the team exists.
  """
  @spec team_exists?(GenServer.server(), team_id()) :: boolean()
  def team_exists?(server, team_id) do
    GenServer.call(server, {:team_exists?, team_id})
  end

  @doc """
  Returns `true` when the user is a member of the team.
  """
  @spec is_member?(GenServer.server(), team_id(), user_id()) :: boolean()
  def is_member?(server, team_id, user_id) do
    GenServer.call(server, {:is_member?, team_id, user_id})
  end

  @doc """
  Returns `{:ok, role}` with the user's role in the team, or `:error` when the
  user is not a member (or the team does not exist).
  """
  @spec role_of(GenServer.server(), team_id(), user_id()) :: {:ok, role()} | :error
  def role_of(server, team_id, user_id) do
    GenServer.call(server, {:role_of, team_id, user_id})
  end

  @doc """
  Lists the memberships of a team as maps with `:user_id` and `:role` keys.

  Returns `{:error, :not_found}` when the team does not exist.
  """
  @spec list_members(GenServer.server(), team_id()) ::
          {:ok, [%{user_id: user_id(), role: role()}]} | {:error, :not_found}
  def list_members(server, team_id) do
    GenServer.call(server, {:list_members, team_id})
  end

  @doc """
  Adds a member with a role, validating the team and rejecting duplicates.

  Returns `{:ok, user_id}`, `{:error, :not_found}` when the team is unknown, or
  `{:error, :conflict}` when the user is already on the team.
  """
  @spec add_member_safe(GenServer.server(), team_id(), user_id(), role()) ::
          {:ok, user_id()} | {:error, :not_found | :conflict}
  def add_member_safe(server, team_id, user_id, role) do
    GenServer.call(server, {:add_member_safe, team_id, user_id, role})
  end

  @doc """
  Removes a member from a team.

  Returns `{:ok, user_id}`, `{:error, :not_found}` when the team is unknown, or
  `{:error, :not_member}` when the user is not on the team.
  """
  @spec remove_member_safe(GenServer.server(), team_id(), user_id()) ::
          {:ok, user_id()} | {:error, :not_found | :not_member}
  def remove_member_safe(server, team_id, user_id) do
    GenServer.call(server, {:remove_member_safe, team_id, user_id})
  end

  @impl GenServer
  def init(:ok), do: {:ok, %__MODULE__{}}

  @impl GenServer
  def handle_call({:create_user, id, token}, _from, state) do
    state = %{
      state
      | users: Map.put(state.users, id, token),
        tokens: Map.put(state.tokens, token, id)
    }

    {:reply, :ok, state}
  end

  def handle_call({:create_team, team_id}, _from, state) do
    state = %{
      state
      | teams: MapSet.put(state.teams, team_id),
        memberships: Map.put_new(state.memberships, team_id, %{})
    }

    {:reply, :ok, state}
  end

  def handle_call({:add_member, team_id, user_id, role}, _from, state) do
    {:reply, :ok, put_membership(state, team_id, user_id, role)}
  end

  def handle_call({:get_user_by_token, token}, _from, state) do
    {:reply, Map.fetch(state.tokens, token), state}
  end

  def handle_call({:team_exists?, team_id}, _from, state) do
    {:reply, MapSet.member?(state.teams, team_id), state}
  end

  def handle_call({:is_member?, team_id, user_id}, _from, state) do
    {:reply, Map.has_key?(members_of(state, team_id), user_id), state}
  end

  def handle_call({:role_of, team_id, user_id}, _from, state) do
    {:reply, Map.fetch(members_of(state, team_id), user_id), state}
  end

  def handle_call({:list_members, team_id}, _from, state) do
    if MapSet.member?(state.teams, team_id) do
      members =
        state
        |> members_of(team_id)
        |> Enum.map(fn {user_id, role} -> %{user_id: user_id, role: role} end)
        |> Enum.sort_by(& &1.user_id)

      {:reply, {:ok, members}, state}
    else
      {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:add_member_safe, team_id, user_id, role}, _from, state) do
    cond do
      not MapSet.member?(state.teams, team_id) ->
        {:reply, {:error, :not_found}, state}

      Map.has_key?(members_of(state, team_id), user_id) ->
        {:reply, {:error, :conflict}, state}

      true ->
        {:reply, {:ok, user_id}, put_membership(state, team_id, user_id, role)}
    end
  end

  def handle_call({:remove_member_safe, team_id, user_id}, _from, state) do
    cond do
      not MapSet.member?(state.teams, team_id) ->
        {:reply, {:error, :not_found}, state}

      not Map.has_key?(members_of(state, team_id), user_id) ->
        {:reply, {:error, :not_member}, state}

      true ->
        members = state |> members_of(team_id) |> Map.delete(user_id)
        {:reply, {:ok, user_id}, %{state | memberships: Map.put(state.memberships, team_id, members)}}
    end
  end

  @spec members_of(%__MODULE__{}, team_id()) :: %{optional(user_id()) => role()}
  defp members_of(state, team_id), do: Map.get(state.memberships, team_id, %{})

  @spec put_membership(%__MODULE__{}, team_id(), user_id(), role()) :: %__MODULE__{}
  defp put_membership(state, team_id, user_id, role) do
    members = state |> members_of(team_id) |> Map.put(user_id, role)
    %{state | memberships: Map.put(state.memberships, team_id, members)}
  end
end

defmodule AuthPlug do
  @moduledoc """
  Bearer-token authentication plug.

  Reads the `authorization` request header, expects a `Bearer <token>` value and
  resolves it to a user via `TeamStore.get_user_by_token/2`. The resolved user id
  is placed in `conn.assigns.current_user`.

  Missing or invalid credentials halt the connection with a 401 JSON body of
  `{"error": "unauthorized"}`.

  Requires a `:store` option at init time, holding the `TeamStore` server
  reference.
  """

  @behaviour Plug

  import Plug.Conn

  @doc """
  Initializes the plug. Expects a `:store` option identifying the `TeamStore`.
  """
  @impl Plug
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @doc """
  Authenticates the request, assigning `:current_user` or halting with 401.
  """
  @impl Plug
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    store = Keyword.fetch!(opts, :store)

    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         token <- String.trim(token),
         true <- token != "",
         {:ok, user_id} <- TeamStore.get_user_by_token(store, token) do
      assign(conn, :current_user, user_id)
    else
      _other -> unauthorized(conn)
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
  Role-scoped nested resource router for team membership.

  Routes:

    * `GET /api/teams/:team_id/members` — any member may read the roster.
    * `POST /api/teams/:team_id/members` — only `owner`/`admin` may add members.
    * `DELETE /api/teams/:team_id/members/:user_id` — only `owner`/`admin` may
      remove members, and only an `owner` may remove an `owner`.

  All responses are `application/json`. The router takes a `:store` option
  identifying the `TeamStore` server, which is threaded through `AuthPlug`.
  """

  use Plug.Router

  @privileged_roles ["owner", "admin"]
  @default_role "member"

  plug :match

  plug Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason

  plug :authenticate
  plug :dispatch, builder_opts()

  @doc """
  Initializes the router. Expects a `:store` option identifying the `TeamStore`.
  """
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @doc """
  Authenticates the connection using `AuthPlug` with the router's `:store`.
  """
  @spec authenticate(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def authenticate(conn, _opts) do
    store = store_from(conn)
    AuthPlug.call(conn, AuthPlug.init(store: store))
  end

  get "/api/teams/:team_id/members" do
    store = Keyword.fetch!(opts, :store)
    caller = conn.assigns.current_user

    cond do
      not TeamStore.team_exists?(store, team_id) ->
        send_json(conn, 404, %{error: "not_found"})

      not TeamStore.is_member?(store, team_id, caller) ->
        send_json(conn, 403, %{error: "forbidden"})

      true ->
        {:ok, members} = TeamStore.list_members(store, team_id)
        send_json(conn, 200, %{members: members})
    end
  end

  post "/api/teams/:team_id/members" do
    store = Keyword.fetch!(opts, :store)
    caller = conn.assigns.current_user

    with {:ok, target, role} <- parse_add_body(conn.body_params),
         :ok <- ensure_team(store, team_id),
         :ok <- ensure_privileged(store, team_id, caller) do
      case TeamStore.add_member_safe(store, team_id, target, role) do
        {:ok, added} -> send_json(conn, 201, %{added: added, role: role})
        {:error, :conflict} -> send_json(conn, 409, %{error: "conflict"})
        {:error, :not_found} -> send_json(conn, 404, %{error: "not_found"})
      end
    else
      {:error, :bad_request} -> send_json(conn, 400, %{error: "bad_request"})
      {:error, :not_found} -> send_json(conn, 404, %{error: "not_found"})
      {:error, :forbidden} -> send_json(conn, 403, %{error: "forbidden"})
    end
  end

  delete "/api/teams/:team_id/members/:user_id" do
    store = Keyword.fetch!(opts, :store)
    caller = conn.assigns.current_user

    with :ok <- ensure_team(store, team_id),
         {:ok, caller_role} <- caller_role(store, team_id, caller),
         :ok <- ensure_target_member(store, team_id, user_id),
         :ok <- ensure_may_remove(store, team_id, user_id, caller_role) do
      case TeamStore.remove_member_safe(store, team_id, user_id) do
        {:ok, removed} -> send_json(conn, 200, %{removed: removed})
        {:error, :not_member} -> send_json(conn, 404, %{error: "not_found"})
        {:error, :not_found} -> send_json(conn, 404, %{error: "not_found"})
      end
    else
      {:error, :not_found} -> send_json(conn, 404, %{error: "not_found"})
      {:error, :forbidden} -> send_json(conn, 403, %{error: "forbidden"})
    end
  end

  match _ do
    send_json(conn, 404, %{error: "not_found"})
  end

  @spec store_from(Plug.Conn.t()) :: GenServer.server()
  defp store_from(conn) do
    conn.private
    |> Map.get(:plug_route_opts, [])
    |> case do
      opts when is_list(opts) -> Keyword.get(opts, :store)
      _other -> nil
    end
    |> case do
      nil -> Process.get(:team_router_store)
      store -> store
    end
  end

  @spec parse_add_body(map()) :: {:ok, String.t(), String.t()} | {:error, :bad_request}
  defp parse_add_body(%{"user_id" => user_id} = params) when is_binary(user_id) do
    role = Map.get(params, "role", @default_role)

    cond do
      user_id == "" -> {:error, :bad_request}
      TeamStore.valid_role?(role) -> {:ok, user_id, role}
      true -> {:error, :bad_request}
    end
  end

  defp parse_add_body(_params), do: {:error, :bad_request}

  @spec ensure_team(GenServer.server(), String.t()) :: :ok | {:error, :not_found}
  defp ensure_team(store, team_id) do
    if TeamStore.team_exists?(store, team_id), do: :ok, else: {:error, :not_found}
  end

  @spec ensure_privileged(GenServer.server(), String.t(), String.t()) ::
          :ok | {:error, :forbidden}
  defp ensure_privileged(store, team_id, caller) do
    case TeamStore.role_of(store, team_id, caller) do
      {:ok, role} when role in @privileged_roles -> :ok
      _other -> {:error, :forbidden}
    end
  end

  @spec caller_role(GenServer.server(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, :forbidden}
  defp caller_role(store, team_id, caller) do
    case TeamStore.role_of(store, team_id, caller) do
      {:ok, role} when role in @privileged_roles -> {:ok, role}
      _other -> {:error, :forbidden}
    end
  end

  @spec ensure_target_member(GenServer.server(), String.t(), String.t()) ::
          :ok | {:error, :not_found}
  defp ensure_target_member(store, team_id, target) do
    if TeamStore.is_member?(store, team_id, target), do: :ok, else: {:error, :not_found}
  end

  @spec ensure_may_remove(GenServer.server(), String.t(), String.t(), String.t()) ::
          :ok | {:error, :forbidden}
  defp ensure_may_remove(store, team_id, target, caller_role) do
    case TeamStore.role_of(store, team_id, target) do
      {:ok, "owner"} when caller_role != "owner" -> {:error, :forbidden}
      _other -> :ok
    end
  end

  @spec send_json(Plug.Conn.t(), pos_integer(), map()) :: Plug.Conn.t()
  defp send_json(conn, status, payload) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(payload))
  end
end