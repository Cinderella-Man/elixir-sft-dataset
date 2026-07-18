# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

## Existing code (your starting point)

```elixir
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
          clock: (-> integer())
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
```

## New specification

Write me an Elixir GenServer module called `QuotaTracker` that tracks per-key usage against configurable rolling-window quotas.

I need these functions in the public API:

- `QuotaTracker.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning the current time in milliseconds. If not provided, default to `fn -> System.monotonic_time(:millisecond) end`. It should also accept a `:name` option for process registration.

- `QuotaTracker.record(server, key, amount, quota, window_ms)` which records `amount` units of usage for the given key against a quota of `quota` within a rolling window of `window_ms` milliseconds. Return `{:ok, remaining}` where remaining is `quota - total_usage_in_window` after recording, or `{:error, :quota_exceeded, overage}` if the recording would push usage above the quota, where `overage` is `(total_usage_in_window + amount) - quota` (the number of units by which the attempted recording overshoots the quota). When the quota would be exceeded, the usage MUST NOT be recorded (all-or-nothing). The per-call `window_ms` only determines which entries are counted for that call — it never removes anything from storage; stored entries are evicted only once they age past the tracker-wide `:max_window_ms` (lazily on access, and via the periodic sweep described below), so an entry outside one call's small window is still counted by a later call that uses a larger window.

- `QuotaTracker.remaining(server, key, quota, window_ms)` which returns `{:ok, remaining}` where remaining is `quota - total_usage_in_window` for the given key. If the key has no recorded usage, remaining equals the full quota. This value is NOT clamped — if usage exceeds the quota, remaining is negative. This is a read-only operation that does not record anything but still performs the lazy cleanup (evicting stored entries older than `:max_window_ms`).

- `QuotaTracker.usage(server, key, window_ms)` which returns `{:ok, total_used}` — the total usage for the key within the rolling window. Returns `{:ok, 0}` if the key has no recorded usage.

- `QuotaTracker.reset(server, key)` which clears all usage history for the given key. Return `:ok` regardless of whether the key existed.

- `QuotaTracker.keys(server)` which returns a list of all keys that have any recorded usage entries (including potentially expired ones — the list is not filtered by the per-call window, though keys are dropped once all their entries age past `:max_window_ms` and are evicted).

Each key tracks usage independently. The rolling window means that usage entries naturally age out — a usage entry recorded at time T is no longer counted once the current time reaches `T + window_ms` (i.e. an entry is counted only while its age is strictly less than `window_ms`). Multiple `record` calls accumulate: if you record 3 then record 5 with a quota of 10, the remaining is 2.

Expired entries should be lazily cleaned up on access, but you also need a periodic sweep so the GenServer doesn't leak memory. Run a periodic cleanup using `Process.send_after` every 60 seconds (configurable via `:cleanup_interval_ms` option) that removes any keys whose usage lists are completely empty after evicting expired entries. Use a configurable `:max_window_ms` option (default 3600000, i.e. 1 hour) for the sweep — entries older than `max_window_ms` from the current time are always evicted regardless of the per-call `window_ms` (an entry is evicted once its age reaches `max_window_ms`).

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.

## Additional interface contract

- The `:cleanup_interval_ms` option may also be `:infinity`, in which case the periodic
  timer is never scheduled — nothing runs automatically.

- Sending the server process a bare `:cleanup` message performs one cleanup
  pass immediately — the same work the periodic timer performs.
