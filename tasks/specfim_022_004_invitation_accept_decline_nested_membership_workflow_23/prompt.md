# Write the missing @spec

Below is a complete, working module — except that the `@spec` for
`invite_member/3` has been removed; its place is marked `# TODO: @spec`.
Write exactly that typespec: one `@spec` attribute for `invite_member/3`,
consistent with the function's arguments, guards, and every return shape
the implementation can produce. Change nothing else.

## The module with the `@spec` for `invite_member/3` missing

```elixir
defmodule TeamStore do
  @moduledoc """
  In-memory state store for teams, users, active members, and pending
  invitations, implemented as a `GenServer`.

  The store models an invitation / RSVP workflow: a member invites another
  user, which creates a *pending* invitation. The invited user must then
  accept the invitation to become an *active* member, or decline it to drop
  the invitation.

  State is kept purely in process memory and is lost when the process stops.
  """

  use GenServer

  @typedoc "Opaque server reference (pid or registered name)."
  @type server :: GenServer.server()

  @typedoc "Internal state held by the GenServer."
  @type state :: %{
          users: %{optional(String.t()) => String.t()},
          tokens: %{optional(String.t()) => String.t()},
          teams: %{
            optional(String.t()) => %{
              members: MapSet.t(String.t()),
              invitations: MapSet.t(String.t())
            }
          }
        }

  # ── Public API ──────────────────────────────────────────────────────────

  @doc """
  Starts the store process.

  Accepts a `:name` option used to register the process. Any other options
  are ignored.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, rest} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, rest, server_opts)
  end

  @doc """
  Stores a user with the given `id` and bearer `token`. Returns `:ok`.
  """
  @spec create_user(server(), String.t(), String.t()) :: :ok
  def create_user(server, id, token) do
    GenServer.call(server, {:create_user, id, token})
  end

  @doc """
  Creates a team with no members and no invitations. Returns `:ok`.
  """
  @spec create_team(server(), String.t()) :: :ok
  def create_team(server, team_id) do
    GenServer.call(server, {:create_team, team_id})
  end

  @doc """
  Adds a user directly as an active member (used for seeding). Returns `:ok`.
  """
  @spec add_member(server(), String.t(), String.t()) :: :ok
  def add_member(server, team_id, user_id) do
    GenServer.call(server, {:add_member, team_id, user_id})
  end

  @doc """
  Looks up a user by bearer token.

  Returns `{:ok, user_id}` when the token is known, otherwise `:error`.
  """
  @spec get_user_by_token(server(), String.t()) :: {:ok, String.t()} | :error
  def get_user_by_token(server, token) do
    GenServer.call(server, {:get_user_by_token, token})
  end

  @doc """
  Returns `true` if the team exists, otherwise `false`.
  """
  @spec team_exists?(server(), String.t()) :: boolean()
  def team_exists?(server, team_id) do
    GenServer.call(server, {:team_exists?, team_id})
  end

  @doc """
  Returns `true` if the user is an active member of the team, else `false`.
  """
  @spec is_member?(server(), String.t(), String.t()) :: boolean()
  def is_member?(server, team_id, user_id) do
    GenServer.call(server, {:is_member?, team_id, user_id})
  end

  @doc """
  Returns `true` if the user has a pending invitation for the team, else
  `false`.
  """
  @spec is_invited?(server(), String.t(), String.t()) :: boolean()
  def is_invited?(server, team_id, user_id) do
    GenServer.call(server, {:is_invited?, team_id, user_id})
  end

  @doc """
  Lists active member IDs for a team.

  Returns `{:ok, member_ids}` or `{:error, :not_found}` if the team does not
  exist.
  """
  @spec list_members(server(), String.t()) ::
          {:ok, [String.t()]} | {:error, :not_found}
  def list_members(server, team_id) do
    GenServer.call(server, {:list_members, team_id})
  end

  @doc """
  Lists pending invitation user IDs for a team.

  Returns `{:ok, user_ids}` or `{:error, :not_found}` if the team does not
  exist.
  """
  @spec list_invitations(server(), String.t()) ::
          {:ok, [String.t()]} | {:error, :not_found}
  def list_invitations(server, team_id) do
    GenServer.call(server, {:list_invitations, team_id})
  end

  @doc """
  Creates a pending invitation for `user_id` on the given team.

  Returns `{:error, :not_found}` if the team does not exist,
  `{:error, :conflict}` if the user is already an active member,
  `{:error, :already_invited}` if the user already has a pending invitation,
  and `{:ok, user_id}` on success.
  """
  # TODO: @spec
  def invite_member(server, team_id, user_id) do
    GenServer.call(server, {:invite_member, team_id, user_id})
  end

  @doc """
  Turns a pending invitation into an active membership.

  Returns `{:error, :not_found}` if the team does not exist,
  `{:error, :no_invitation}` if the user has no pending invitation, and
  `{:ok, user_id}` on success.
  """
  @spec accept_invite(server(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, :not_found | :no_invitation}
  def accept_invite(server, team_id, user_id) do
    GenServer.call(server, {:accept_invite, team_id, user_id})
  end

  @doc """
  Removes a pending invitation without adding the user as a member.

  Returns `{:error, :not_found}` if the team does not exist,
  `{:error, :no_invitation}` if the user has no pending invitation, and
  `{:ok, user_id}` on success.
  """
  @spec decline_invite(server(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, :not_found | :no_invitation}
  def decline_invite(server, team_id, user_id) do
    GenServer.call(server, {:decline_invite, team_id, user_id})
  end

  # ── GenServer callbacks ─────────────────────────────────────────────────

  @impl true
  @spec init(term()) :: {:ok, state()}
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

  @spec new_team() :: %{members: MapSet.t(String.t()), invitations: MapSet.t(String.t())}
  defp new_team do
    %{members: MapSet.new(), invitations: MapSet.new()}
  end

  @spec put_team(state(), String.t(), map()) :: state()
  defp put_team(state, team_id, team) do
    %{state | teams: Map.put(state.teams, team_id, team)}
  end
end

defmodule AuthPlug do
  @moduledoc """
  Plug that authenticates a request via a `Bearer <token>` authorization
  header.

  The token is resolved to a user through `TeamStore.get_user_by_token/2`.
  On success the resolved user ID is assigned to `conn.assigns.current_user`.
  On failure the connection is halted with a `401` JSON response.

  The `TeamStore` process to query is taken from `conn.private[:team_store]`
  when present (stashed by `TeamRouter`), otherwise from the `:store` init
  option, defaulting to the `TeamStore` module name.

  Authentication only proves that the token maps to a real user; it does not
  require the user to be a member of any team.
  """

  import Plug.Conn

  @behaviour Plug

  @doc """
  Initializes the plug.

  Accepts a `:store` option identifying the `TeamStore` process to query as a
  fallback when the connection does not carry one in `conn.private`.
  """
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @doc """
  Authenticates the connection.

  Reads the `authorization` header, expects a `Bearer <token>` value, and
  assigns `:current_user` when the token resolves to a user. Otherwise halts
  with a `401` unauthorized JSON response.
  """
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
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
  `Plug.Router` exposing nested team-membership endpoints built around an
  invitation / RSVP workflow.

  Every request is authenticated by `AuthPlug` before route matching. The
  router expects a `:store` option (a `TeamStore` process) which is stashed
  in `conn.private` so both `AuthPlug` and the route handlers can reach it.

  Endpoint checks are applied in a fixed order: team existence first, then
  authorization, then operation-specific outcomes.
  """

  use Plug.Router

  plug(:match)

  plug(AuthPlug, store: Application.compile_env(:team_app, :store, TeamStore))

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason
  )

  plug(:dispatch)

  @doc """
  Builds the router's plug pipeline for the given options.

  Accepts a `:store` option identifying the `TeamStore` process; it is stashed
  in `conn.private` so both `AuthPlug` and handlers can reach it.
  """
  @spec init(keyword()) :: keyword()
  def init(opts), do: super(opts)

  @doc """
  Entry point invoked by Plug for each connection.

  Stashes the configured `:store` into `conn.private` before running the
  router pipeline.
  """
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    store = Map.get(conn.private, :team_store) || Keyword.get(opts, :store, TeamStore)
    conn = put_private(conn, :team_store, store)
    super(conn, opts)
  end

  # AuthPlug needs the store at match time; resolve it from conn.private.
  defoverridable call: 2

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

  @spec store(Plug.Conn.t()) :: TeamStore.server()
  defp store(conn), do: Map.get(conn.private, :team_store, TeamStore)

  @spec with_team_and_member(
          Plug.Conn.t(),
          TeamStore.server(),
          String.t(),
          (-> Plug.Conn.t())
        ) :: Plug.Conn.t()
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

  @spec with_own_invitation(
          Plug.Conn.t(),
          TeamStore.server(),
          String.t(),
          String.t(),
          (-> Plug.Conn.t())
        ) :: Plug.Conn.t()
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

  @spec handle_invite(Plug.Conn.t(), TeamStore.server(), String.t()) :: Plug.Conn.t()
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

  @spec send_json(Plug.Conn.t(), non_neg_integer(), map()) :: Plug.Conn.t()
  defp send_json(conn, status, payload) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(payload))
  end
end
```

Give me only the `@spec` attribute — the attribute alone (however many
lines it spans), not the whole module.
