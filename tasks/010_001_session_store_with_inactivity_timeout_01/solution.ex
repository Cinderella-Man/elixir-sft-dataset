defmodule SessionStore do
  @moduledoc """
  A GenServer that manages user sessions with sliding-window expiration.

  Each session is stored with a `last_active` timestamp. Expiration is checked
  lazily on every access and proactively via a periodic sweep.

  ## Options

    * `:name`               - process registration name (optional)
    * `:timeout_ms`         - inactivity timeout in ms (default: 1_800_000 / 30 min)
    * `:cleanup_interval_ms`- how often the sweep runs in ms (default: 60_000 / 1 min)
    * `:clock`              - zero-arity fn returning current time in ms;
                              defaults to `fn -> System.monotonic_time(:millisecond) end`

  ## Examples

      {:ok, pid} = SessionStore.start_link(timeout_ms: 5_000)

      {:ok, id} = SessionStore.create(pid, %{user_id: 42})
      {:ok, %{user_id: 42}} = SessionStore.get(pid, id)

      :ok = SessionStore.touch(pid, id)
      {:ok, %{user_id: 99}} = SessionStore.update(pid, id, %{user_id: 99})

      :ok = SessionStore.destroy(pid, id)
      {:error, :not_found} = SessionStore.get(pid, id)
  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Types
  # ---------------------------------------------------------------------------

  @type server :: GenServer.server()
  @type session_id :: String.t()
  @type session_data :: term()

  @type session :: %{
          data: session_data(),
          last_active: integer()
        }

  @type state :: %{
          sessions: %{session_id() => session()},
          timeout_ms: non_neg_integer(),
          cleanup_interval_ms: non_neg_integer(),
          clock: (() -> integer())
        }

  # ---------------------------------------------------------------------------
  # Defaults
  # ---------------------------------------------------------------------------

  @default_timeout_ms 1_800_000
  @default_cleanup_interval_ms 60_000
  @default_clock &__MODULE__.__default_clock__/0

  # Public so the default fn literal can reference it without capturing a
  # private function (which would break in some compilation contexts).
  @doc false
  def __default_clock__, do: System.monotonic_time(:millisecond)

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the `SessionStore` process.

  ## Options

    * `:name`                - passed directly to `GenServer.start_link/3`
    * `:timeout_ms`          - session inactivity timeout (default #{@default_timeout_ms} ms)
    * `:cleanup_interval_ms` - sweep interval (default #{@default_cleanup_interval_ms} ms)
    * `:clock`               - zero-arity fn returning current time in ms
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name_opt, init_opts} =
      case Keyword.pop(opts, :name) do
        {nil, rest} -> {[], rest}
        {name, rest} -> {[name: name], rest}
      end

    GenServer.start_link(__MODULE__, init_opts, name_opt)
  end

  @doc """
  Creates a new session containing `session_data`.

  Returns `{:ok, session_id}`. The inactivity timer starts immediately.
  """
  @spec create(server(), session_data()) :: {:ok, session_id()}
  def create(server, session_data) do
    GenServer.call(server, {:create, session_data})
  end

  @doc """
  Retrieves session data for `session_id`.

  Returns `{:ok, data}` and resets the inactivity timer, or
  `{:error, :not_found}` if the session is missing or has expired.
  """
  @spec get(server(), session_id()) :: {:ok, session_data()} | {:error, :not_found}
  def get(server, session_id) do
    GenServer.call(server, {:get, session_id})
  end

  @doc """
  Replaces the stored data for `session_id` with `new_data`.

  Returns `{:ok, new_data}` and resets the inactivity timer, or
  `{:error, :not_found}` if the session is missing or has expired.
  """
  @spec update(server(), session_id(), session_data()) ::
          {:ok, session_data()} | {:error, :not_found}
  def update(server, session_id, new_data) do
    GenServer.call(server, {:update, session_id, new_data})
  end

  @doc """
  Resets the inactivity timer for `session_id` without changing its data.

  Returns `:ok` on success or `{:error, :not_found}` if the session is
  missing or has expired.
  """
  @spec touch(server(), session_id()) :: :ok | {:error, :not_found}
  def touch(server, session_id) do
    GenServer.call(server, {:touch, session_id})
  end

  @doc """
  Immediately removes the session identified by `session_id`.

  Always returns `:ok`, even if the session did not exist.
  """
  @spec destroy(server(), session_id()) :: :ok
  def destroy(server, session_id) do
    GenServer.call(server, {:destroy, session_id})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)
    clock = Keyword.get(opts, :clock, @default_clock)

    state = %{
      sessions: %{},
      timeout_ms: timeout_ms,
      cleanup_interval_ms: cleanup_interval_ms,
      clock: clock
    }

    schedule_cleanup(cleanup_interval_ms)
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:create, session_data}, _from, state) do
    session_id = generate_session_id()
    now = state.clock.()

    session = %{data: session_data, last_active: now}
    new_sessions = Map.put(state.sessions, session_id, session)

    {:reply, {:ok, session_id}, %{state | sessions: new_sessions}}
  end

  def handle_call({:get, session_id}, _from, state) do
    now = state.clock.()

    case fetch_live_session(state.sessions, session_id, now, state.timeout_ms) do
      {:ok, session} ->
        updated_session = %{session | last_active: now}
        new_sessions = Map.put(state.sessions, session_id, updated_session)
        {:reply, {:ok, session.data}, %{state | sessions: new_sessions}}

      :expired ->
        new_sessions = Map.delete(state.sessions, session_id)
        {:reply, {:error, :not_found}, %{state | sessions: new_sessions}}

      :missing ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:update, session_id, new_data}, _from, state) do
    now = state.clock.()

    case fetch_live_session(state.sessions, session_id, now, state.timeout_ms) do
      {:ok, session} ->
        updated_session = %{session | data: new_data, last_active: now}
        new_sessions = Map.put(state.sessions, session_id, updated_session)
        {:reply, {:ok, new_data}, %{state | sessions: new_sessions}}

      :expired ->
        new_sessions = Map.delete(state.sessions, session_id)
        {:reply, {:error, :not_found}, %{state | sessions: new_sessions}}

      :missing ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:touch, session_id}, _from, state) do
    now = state.clock.()

    case fetch_live_session(state.sessions, session_id, now, state.timeout_ms) do
      {:ok, session} ->
        updated_session = %{session | last_active: now}
        new_sessions = Map.put(state.sessions, session_id, updated_session)
        {:reply, :ok, %{state | sessions: new_sessions}}

      :expired ->
        new_sessions = Map.delete(state.sessions, session_id)
        {:reply, {:error, :not_found}, %{state | sessions: new_sessions}}

      :missing ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:destroy, session_id}, _from, state) do
    new_sessions = Map.delete(state.sessions, session_id)
    {:reply, :ok, %{state | sessions: new_sessions}}
  end

  @impl GenServer
  def handle_info(:cleanup, state) do
    now = state.clock.()

    surviving_sessions =
      Map.filter(state.sessions, fn {_id, session} ->
        not expired?(session, now, state.timeout_ms)
      end)

    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, %{state | sessions: surviving_sessions}}
  end

  # Catch-all for unexpected messages — keeps the process alive and logs.
  def handle_info(msg, state) do
    require Logger
    Logger.warning("#{__MODULE__} received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Generates a URL-safe, base64-encoded, 16-byte random session ID (~22 chars).
  @spec generate_session_id() :: session_id()
  defp generate_session_id do
    :crypto.strong_rand_bytes(16)
    |> Base.url_encode64(padding: false)
  end

  # Schedules the next periodic sweep.
  defp schedule_cleanup(interval_ms) when is_integer(interval_ms) do
    Process.send_after(self(), :cleanup, interval_ms)
  end

  defp schedule_cleanup(_), do: :ok

  # Returns whether a session's sliding deadline has passed.
  @spec expired?(session(), integer(), non_neg_integer()) :: boolean()
  defp expired?(session, now, timeout_ms) do
    now - session.last_active >= timeout_ms
  end

  # Looks up a session and classifies it as live, expired, or missing.
  @spec fetch_live_session(
          %{session_id() => session()},
          session_id(),
          integer(),
          non_neg_integer()
        ) :: {:ok, session()} | :expired | :missing
  defp fetch_live_session(sessions, session_id, now, timeout_ms) do
    case Map.fetch(sessions, session_id) do
      {:ok, session} ->
        if expired?(session, now, timeout_ms), do: :expired, else: {:ok, session}

      :error ->
        :missing
    end
  end
end
