# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `handle_call` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me a set of Elixir modules that implement **nested resource endpoints for team membership with optimistic concurrency control**, using only `Plug` and standard OTP (no Phoenix, no database, no external dependencies beyond `plug` and `jason`).

Every team carries a monotonically increasing **version** number. Mutations must present the version they expect to update via an `If-Match` request header; if the version has moved on, the write is rejected. This lets concurrent clients detect lost updates.

I need these modules:

**`TeamStore`** — a GenServer that holds all application state in memory (users, teams, memberships, and per-team version numbers). It should support these public functions:

- `TeamStore.start_link(opts)` — starts the process. Accepts a `:name` option for registration.
- `TeamStore.create_user(server, id, token)` — stores a user with the given ID and bearer token. Returns `:ok`.
- `TeamStore.create_team(server, team_id)` — creates a team with an empty member list and **version `0`**. Returns `:ok`.
- `TeamStore.add_member(server, team_id, user_id)` — adds a user to a team directly (for seeding). Adding a not-yet-present user **increments the team's version by 1**; adding a user already on the team is a no-op that leaves the version unchanged. Returns `:ok`.
- `TeamStore.get_user_by_token(server, token)` — returns `{:ok, user_id}` or `:error`.
- `TeamStore.team_exists?(server, team_id)` — returns `true` or `false`.
- `TeamStore.is_member?(server, team_id, user_id)` — returns `true` or `false`.
- `TeamStore.get_version(server, team_id)` — returns `{:ok, version}` or `{:error, :not_found}`.
- `TeamStore.list_members(server, team_id)` — returns `{:ok, list_of_user_ids}` or `{:error, :not_found}`.
- `TeamStore.add_member_safe(server, team_id, user_id, expected_version)` — atomically adds a member only if all of the following hold. Checks are performed in this order:
  1. If the team does not exist, returns `{:error, :not_found}`.
  2. If `expected_version` does not equal the team's current version, returns `{:error, :stale}`.
  3. If the user is already a member, returns `{:error, :conflict}`.
  4. Otherwise it appends the user, increments the version by 1, and returns `{:ok, user_id, new_version}`.

**`AuthPlug`** — a Plug that reads the `authorization` header, expects `Bearer <token>`, looks the user up via `TeamStore.get_user_by_token/2`, and assigns `:current_user` to the conn. If the token is missing or invalid, it halts the connection with a 401 JSON response `{"error": "unauthorized"}`. It should accept a `:store` option at init time to know which TeamStore process to call.

**`TeamRouter`** — a `Plug.Router` that serves the following endpoints. It should accept a `:store` option and plug `AuthPlug` before route matching.

- `GET /api/teams/:team_id/members` — If the team doesn't exist, return 404 `{"error": "not_found"}`. If the current user is not a member of the team, return 403 `{"error": "forbidden"}`. Otherwise return 200 `{"members": [list_of_user_ids], "version": version}` and set a response header `ETag` whose value is the version rendered as a string (e.g. version `2` → `ETag: 2`).

- `POST /api/teams/:team_id/members` — Reads a JSON body with `{"user_id": "..."}`. The response is decided in this order:
  1. If the team doesn't exist, return 404 `{"error": "not_found"}`.
  2. If the current user is not a member of the team, return 403 `{"error": "forbidden"}`.
  3. If there is no `If-Match` request header, return 428 `{"error": "precondition_required"}`.
  4. If the body is missing a string `"user_id"` field, return 400 `{"error": "bad_request"}`.
  5. Interpret the `If-Match` header value as the expected version (an integer; a non-integer value is treated as a version that can never match). Call `add_member_safe/4` with it. Map its result: `{:error, :stale}` → 412 `{"error": "precondition_failed"}`; `{:error, :conflict}` → 409 `{"error": "conflict"}`; `{:error, :not_found}` → 404 `{"error": "not_found"}`; `{:ok, user_id, new_version}` → 201 `{"added": user_id, "version": new_version}` with a response header `ETag` equal to the new version rendered as a string.

Because every successful write bumps the version, a client that reads the version, then performs a write, invalidates any other client still holding the old version — a second write presenting the now-stale version gets 412.

All error and success responses must be `application/json`. Give me all modules in a single file. Use only `plug`, `jason`, and the OTP standard library.

## The module with `handle_call` missing

```elixir
defmodule TeamStore do
  @moduledoc """
  In-memory state store for users, teams, memberships, and per-team version
  numbers, implemented as a `GenServer`.

  Every team tracks a monotonically increasing version. Membership mutations
  bump the version, which enables optimistic concurrency control: a client that
  presents a stale version when writing is rejected so that lost updates can be
  detected.
  """

  use GenServer

  @typedoc "Opaque server reference — a pid or registered name."
  @type server :: GenServer.server()

  @typedoc "Internal server state."
  @type state :: %{
          users: %{optional(String.t()) => String.t()},
          tokens: %{optional(String.t()) => String.t()},
          teams: %{optional(String.t()) => %{members: [String.t()], version: non_neg_integer()}}
        }

  # -- Client API ------------------------------------------------------------

  @doc """
  Starts the store process.

  Accepts a `:name` option used to register the process.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, rest} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, rest, gen_opts)
  end

  @doc """
  Stores a user with the given `id` and bearer `token`.
  """
  @spec create_user(server(), String.t(), String.t()) :: :ok
  def create_user(server, id, token) do
    GenServer.call(server, {:create_user, id, token})
  end

  @doc """
  Creates a team with an empty member list and version `0`.
  """
  @spec create_team(server(), String.t()) :: :ok
  def create_team(server, team_id) do
    GenServer.call(server, {:create_team, team_id})
  end

  @doc """
  Adds a user to a team directly (for seeding).

  Adding a not-yet-present user increments the team's version by 1; adding a
  user already present is a no-op that leaves the version unchanged.
  """
  @spec add_member(server(), String.t(), String.t()) :: :ok
  def add_member(server, team_id, user_id) do
    GenServer.call(server, {:add_member, team_id, user_id})
  end

  @doc """
  Looks up a user id by bearer token.

  Returns `{:ok, user_id}` or `:error`.
  """
  @spec get_user_by_token(server(), String.t()) :: {:ok, String.t()} | :error
  def get_user_by_token(server, token) do
    GenServer.call(server, {:get_user_by_token, token})
  end

  @doc """
  Returns whether a team exists.
  """
  @spec team_exists?(server(), String.t()) :: boolean()
  def team_exists?(server, team_id) do
    GenServer.call(server, {:team_exists?, team_id})
  end

  @doc """
  Returns whether `user_id` is a member of `team_id`.
  """
  @spec is_member?(server(), String.t(), String.t()) :: boolean()
  def is_member?(server, team_id, user_id) do
    GenServer.call(server, {:is_member?, team_id, user_id})
  end

  @doc """
  Returns `{:ok, version}` for the team, or `{:error, :not_found}`.
  """
  @spec get_version(server(), String.t()) :: {:ok, non_neg_integer()} | {:error, :not_found}
  def get_version(server, team_id) do
    GenServer.call(server, {:get_version, team_id})
  end

  @doc """
  Returns `{:ok, list_of_user_ids}` for the team, or `{:error, :not_found}`.
  """
  @spec list_members(server(), String.t()) :: {:ok, [String.t()]} | {:error, :not_found}
  def list_members(server, team_id) do
    GenServer.call(server, {:list_members, team_id})
  end

  @doc """
  Atomically adds a member only if all preconditions hold, in this order:

    1. team must exist, else `{:error, :not_found}`;
    2. `expected_version` must equal the current version, else `{:error, :stale}`;
    3. the user must not already be a member, else `{:error, :conflict}`;
    4. otherwise append the user, bump the version, and return
       `{:ok, user_id, new_version}`.
  """
  @spec add_member_safe(server(), String.t(), String.t(), integer()) ::
          {:ok, String.t(), non_neg_integer()}
          | {:error, :not_found | :stale | :conflict}
  def add_member_safe(server, team_id, user_id, expected_version) do
    GenServer.call(server, {:add_member_safe, team_id, user_id, expected_version})
  end

  # -- Server callbacks ------------------------------------------------------

  @impl true
  @spec init(keyword()) :: {:ok, state()}
  def init(_opts) do
    {:ok, %{users: %{}, tokens: %{}, teams: %{}}}
  end

  def handle_call({:create_user, id, token}, _from, state) do
    # TODO
  end
end

defmodule AuthPlug do
  @moduledoc """
  A `Plug` that authenticates requests via a bearer token.

  It reads the `authorization` header, expects the form `Bearer <token>`, and
  resolves the token through `TeamStore.get_user_by_token/2`. On success it
  assigns `:current_user` to the connection; otherwise it halts with a 401 JSON
  response.

  Requires a `:store` option at init time identifying the `TeamStore` process.
  """

  @behaviour Plug

  import Plug.Conn

  @doc """
  Initializes the plug, requiring a `:store` option.
  """
  @spec init(keyword()) :: keyword()
  def init(opts) do
    unless Keyword.has_key?(opts, :store) do
      raise ArgumentError, "AuthPlug requires a :store option"
    end

    opts
  end

  @doc """
  Authenticates the connection, assigning `:current_user` or halting with 401.
  """
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    store = Keyword.fetch!(opts, :store)

    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, user_id} <- TeamStore.get_user_by_token(store, token) do
      assign(conn, :current_user, user_id)
    else
      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "unauthorized"}))
        |> halt()
    end
  end
end

defmodule TeamRouter do
  @moduledoc """
  A `Plug.Router` exposing nested team-membership endpoints with optimistic
  concurrency control.

  Reads use the team version as an `ETag`; writes must present the expected
  version via an `If-Match` request header and are rejected when that version is
  stale. Requires a `:store` option and runs `AuthPlug` before route matching.
  """

  use Plug.Router

  @doc """
  Builds the router options; requires and forwards the `:store` option.
  """
  @spec init(keyword()) :: keyword()
  def init(opts) do
    unless Keyword.has_key?(opts, :store) do
      raise ArgumentError, "TeamRouter requires a :store option"
    end

    opts
  end

  @doc """
  Entry point; stashes the `:store` option on the conn and dispatches.
  """
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    store = Keyword.fetch!(opts, :store)
    conn = put_private(conn, :team_store, store)
    super(conn, opts)
  end

  plug(:store_auth)
  plug(:match)

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason
  )

  plug(:dispatch)

  get "/api/teams/:team_id/members" do
    store = conn.private.team_store
    user = conn.assigns.current_user

    cond do
      not TeamStore.team_exists?(store, team_id) ->
        send_json(conn, 404, %{error: "not_found"})

      not TeamStore.is_member?(store, team_id, user) ->
        send_json(conn, 403, %{error: "forbidden"})

      true ->
        {:ok, members} = TeamStore.list_members(store, team_id)
        {:ok, version} = TeamStore.get_version(store, team_id)

        conn
        |> Plug.Conn.put_resp_header("etag", Integer.to_string(version))
        |> send_json(200, %{members: members, version: version})
    end
  end

  post "/api/teams/:team_id/members" do
    store = conn.private.team_store
    user = conn.assigns.current_user

    cond do
      not TeamStore.team_exists?(store, team_id) ->
        send_json(conn, 404, %{error: "not_found"})

      not TeamStore.is_member?(store, team_id, user) ->
        send_json(conn, 403, %{error: "forbidden"})

      true ->
        handle_add(conn, store, team_id)
    end
  end

  match _ do
    send_json(conn, 404, %{error: "not_found"})
  end

  # -- Helpers ---------------------------------------------------------------

  @spec store_auth(Plug.Conn.t(), any()) :: Plug.Conn.t()
  defp store_auth(conn, _opts) do
    AuthPlug.call(conn, AuthPlug.init(store: conn.private.team_store))
  end

  @spec handle_add(Plug.Conn.t(), TeamStore.server(), String.t()) :: Plug.Conn.t()
  defp handle_add(conn, store, team_id) do
    case Plug.Conn.get_req_header(conn, "if-match") do
      [] ->
        send_json(conn, 428, %{error: "precondition_required"})

      [if_match | _] ->
        with_user_id(conn, store, team_id, if_match)
    end
  end

  @spec with_user_id(Plug.Conn.t(), TeamStore.server(), String.t(), String.t()) ::
          Plug.Conn.t()
  defp with_user_id(conn, store, team_id, if_match) do
    case conn.body_params do
      %{"user_id" => user_id} when is_binary(user_id) ->
        apply_add(conn, store, team_id, user_id, parse_version(if_match))

      _ ->
        send_json(conn, 400, %{error: "bad_request"})
    end
  end

  @spec apply_add(
          Plug.Conn.t(),
          TeamStore.server(),
          String.t(),
          String.t(),
          integer()
        ) :: Plug.Conn.t()
  defp apply_add(conn, store, team_id, user_id, expected_version) do
    case TeamStore.add_member_safe(store, team_id, user_id, expected_version) do
      {:ok, added, new_version} ->
        conn
        |> Plug.Conn.put_resp_header("etag", Integer.to_string(new_version))
        |> send_json(201, %{added: added, version: new_version})

      {:error, :stale} ->
        send_json(conn, 412, %{error: "precondition_failed"})

      {:error, :conflict} ->
        send_json(conn, 409, %{error: "conflict"})

      {:error, :not_found} ->
        send_json(conn, 404, %{error: "not_found"})
    end
  end

  # Interpret the header as an integer version. A non-integer value yields a
  # sentinel (-1) that can never match a real, non-negative version.
  @spec parse_version(String.t()) :: integer()
  defp parse_version(value) do
    case Integer.parse(String.trim(value)) do
      {version, ""} -> version
      _ -> -1
    end
  end

  @spec send_json(Plug.Conn.t(), non_neg_integer(), map()) :: Plug.Conn.t()
  defp send_json(conn, status, payload) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(payload))
  end
end
```

Give me only the complete implementation of `handle_call` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
