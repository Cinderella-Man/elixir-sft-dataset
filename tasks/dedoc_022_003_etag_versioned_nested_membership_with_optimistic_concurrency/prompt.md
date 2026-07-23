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

  # -- Client API ------------------------------------------------------------

  def start_link(opts) do
    {name, rest} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, rest, gen_opts)
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

  def get_version(server, team_id) do
    GenServer.call(server, {:get_version, team_id})
  end

  def list_members(server, team_id) do
    GenServer.call(server, {:list_members, team_id})
  end

  def add_member_safe(server, team_id, user_id, expected_version) do
    GenServer.call(server, {:add_member_safe, team_id, user_id, expected_version})
  end

  # -- Server callbacks ------------------------------------------------------

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
    teams = Map.put_new(state.teams, team_id, %{members: [], version: 0})
    {:reply, :ok, %{state | teams: teams}}
  end

  def handle_call({:add_member, team_id, user_id}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      {:ok, %{members: members, version: version} = team} ->
        if user_id in members do
          {:reply, :ok, state}
        else
          team = %{team | members: members ++ [user_id], version: version + 1}
          {:reply, :ok, %{state | teams: Map.put(state.teams, team_id, team)}}
        end

      :error ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:get_user_by_token, token}, _from, state) do
    {:reply, Map.fetch(state.tokens, token), state}
  end

  def handle_call({:team_exists?, team_id}, _from, state) do
    {:reply, Map.has_key?(state.teams, team_id), state}
  end

  def handle_call({:is_member?, team_id, user_id}, _from, state) do
    member? =
      case Map.fetch(state.teams, team_id) do
        {:ok, %{members: members}} -> user_id in members
        :error -> false
      end

    {:reply, member?, state}
  end

  def handle_call({:get_version, team_id}, _from, state) do
    reply =
      case Map.fetch(state.teams, team_id) do
        {:ok, %{version: version}} -> {:ok, version}
        :error -> {:error, :not_found}
      end

    {:reply, reply, state}
  end

  def handle_call({:list_members, team_id}, _from, state) do
    reply =
      case Map.fetch(state.teams, team_id) do
        {:ok, %{members: members}} -> {:ok, members}
        :error -> {:error, :not_found}
      end

    {:reply, reply, state}
  end

  def handle_call({:add_member_safe, team_id, user_id, expected_version}, _from, state) do
    case Map.fetch(state.teams, team_id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, %{version: version}} when version != expected_version ->
        {:reply, {:error, :stale}, state}

      {:ok, %{members: members, version: version} = team} ->
        if user_id in members do
          {:reply, {:error, :conflict}, state}
        else
          new_version = version + 1
          team = %{team | members: members ++ [user_id], version: new_version}
          state = %{state | teams: Map.put(state.teams, team_id, team)}
          {:reply, {:ok, user_id, new_version}, state}
        end
    end
  end
end

defmodule AuthPlug do
  @behaviour Plug

  import Plug.Conn

  def init(opts) do
    unless Keyword.has_key?(opts, :store) do
      raise ArgumentError, "AuthPlug requires a :store option"
    end

    opts
  end

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
  use Plug.Router

  def init(opts) do
    unless Keyword.has_key?(opts, :store) do
      raise ArgumentError, "TeamRouter requires a :store option"
    end

    opts
  end

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

  defp store_auth(conn, _opts) do
    AuthPlug.call(conn, AuthPlug.init(store: conn.private.team_store))
  end

  defp handle_add(conn, store, team_id) do
    case Plug.Conn.get_req_header(conn, "if-match") do
      [] ->
        send_json(conn, 428, %{error: "precondition_required"})

      [if_match | _] ->
        with_user_id(conn, store, team_id, if_match)
    end
  end

  defp with_user_id(conn, store, team_id, if_match) do
    case conn.body_params do
      %{"user_id" => user_id} when is_binary(user_id) ->
        apply_add(conn, store, team_id, user_id, parse_version(if_match))

      _ ->
        send_json(conn, 400, %{error: "bad_request"})
    end
  end

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
  defp parse_version(value) do
    case Integer.parse(String.trim(value)) do
      {version, ""} -> version
      _ -> -1
    end
  end

  defp send_json(conn, status, payload) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(payload))
  end
end
```
