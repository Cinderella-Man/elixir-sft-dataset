# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

# Design Brief: `QuotaTracker`

## Problem & Constraints

We need an Elixir GenServer module called `QuotaTracker` that tracks per-key usage against configurable rolling-window quotas. Each key tracks usage independently.

Constraints and background behavior that shape the whole design:

- The rolling window means usage entries naturally age out — a usage entry recorded at time T is no longer counted once the current time reaches `T + window_ms` (i.e. an entry is counted only while its age is strictly less than `window_ms`).
- Multiple `record` calls accumulate: if you record 3 then record 5 with a quota of 10, the remaining is 2.
- Expired entries should be lazily cleaned up on access, but you also need a periodic sweep so the GenServer doesn't leak memory. Run a periodic cleanup using `Process.send_after` every 60 seconds (configurable via `:cleanup_interval_ms` option) that removes any keys whose usage lists are completely empty after evicting expired entries.
- Use a configurable `:max_window_ms` option (default 3600000, i.e. 1 hour) for the sweep — entries older than `max_window_ms` from the current time are always evicted regardless of the per-call `window_ms` (an entry is evicted once its age reaches `max_window_ms`).
- Deliver the complete module in a single file. Use only OTP standard library, no external dependencies.

## Required Interface

1. `QuotaTracker.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning the current time in milliseconds. If not provided, default to `fn -> System.monotonic_time(:millisecond) end`. It should also accept a `:name` option for process registration.

2. `QuotaTracker.record(server, key, amount, quota, window_ms)` which records `amount` units of usage for the given key against a quota of `quota` within a rolling window of `window_ms` milliseconds. Return `{:ok, remaining}` where remaining is `quota - total_usage_in_window` after recording, or `{:error, :quota_exceeded, overage}` if the recording would push usage above the quota, where `overage` is `(total_usage_in_window + amount) - quota` (the number of units by which the attempted recording overshoots the quota). When the quota would be exceeded, the usage MUST NOT be recorded (all-or-nothing). The per-call `window_ms` only determines which entries are counted for that call — it never removes anything from storage; stored entries are evicted only once they age past the tracker-wide `:max_window_ms` (lazily on access, and via the periodic sweep described above), so an entry outside one call's small window is still counted by a later call that uses a larger window.

3. `QuotaTracker.remaining(server, key, quota, window_ms)` which returns `{:ok, remaining}` where remaining is `quota - total_usage_in_window` for the given key. If the key has no recorded usage, remaining equals the full quota. This value is NOT clamped — if usage exceeds the quota, remaining is negative. This is a read-only operation that does not record anything but still performs the lazy cleanup (evicting stored entries older than `:max_window_ms`).

4. `QuotaTracker.usage(server, key, window_ms)` which returns `{:ok, total_used}` — the total usage for the key within the rolling window. Returns `{:ok, 0}` if the key has no recorded usage.

5. `QuotaTracker.reset(server, key)` which clears all usage history for the given key. Return `:ok` regardless of whether the key existed.

6. `QuotaTracker.keys(server)` which returns a list of all keys that have any recorded usage entries (including potentially expired ones — the list is not filtered by the per-call window, though keys are dropped once all their entries age past `:max_window_ms` and are evicted).

7. The `:cleanup_interval_ms` option may also be `:infinity`, in which case the periodic timer is never scheduled — nothing runs automatically.

8. Sending the server process a bare `:cleanup` message performs one cleanup pass immediately — the same work the periodic timer performs.

## Acceptance Criteria

- `record` returns `{:ok, remaining}` with `remaining = quota - total_usage_in_window` after recording, and `{:error, :quota_exceeded, overage}` with `overage = (total_usage_in_window + amount) - quota` when the recording would push usage above the quota; in the exceeded case the usage is not recorded (all-or-nothing).
- The per-call `window_ms` only selects which entries are counted for that call and never removes anything from storage; eviction happens only once entries age past `:max_window_ms`.
- `remaining` returns `{:ok, quota - total_usage_in_window}`, equals the full quota when there is no recorded usage, is unclamped (negative when usage exceeds quota), records nothing, and still performs the lazy cleanup evicting entries older than `:max_window_ms`.
- `usage` returns `{:ok, total_used}` for the rolling window, and `{:ok, 0}` when the key has no recorded usage.
- `reset` clears the key's history and returns `:ok` whether or not the key existed.
- `keys` lists every key with any recorded entries (unfiltered by per-call window), dropping keys only once all their entries age past `:max_window_ms` and are evicted.
- Entries are counted only while their age is strictly less than `window_ms`; accumulation across multiple `record` calls behaves as described.
- The periodic sweep uses `Process.send_after` at the `:cleanup_interval_ms` interval (default 60 seconds), removes keys whose usage lists are empty after evicting expired entries, and uses `:max_window_ms` (default 3600000) so entries reaching that age are always evicted regardless of per-call `window_ms`.
- With `:cleanup_interval_ms` set to `:infinity`, no periodic timer is scheduled and nothing runs automatically.
- A bare `:cleanup` message triggers one immediate cleanup pass identical to the periodic timer's work.
- `start_link/1` honors `:clock` (defaulting to `fn -> System.monotonic_time(:millisecond) end`) and `:name` for registration.
- The deliverable is the complete module in a single file using only the OTP standard library, with no external dependencies.

## The buggy module

```elixir
defmodule QuotaTracker do
  @moduledoc """
  A GenServer that tracks per-key usage against configurable rolling-window quotas.

  Each key maintains a list of timestamped usage entries. Entries age out of
  the rolling window automatically, and usage is checked against a caller-supplied
  quota on each `record` call.

  ## Options

    * `:name`               - process registration name (optional)
    * `:max_window_ms`      - maximum retention for sweep (default: 3_600_000 / 1 hour)
    * `:cleanup_interval_ms`- how often the sweep runs in ms (default: 60_000 / 1 min)
    * `:clock`              - zero-arity fn returning current time in ms;
                              defaults to `fn -> System.monotonic_time(:millisecond) end`

  ## Examples

      {:ok, pid} = QuotaTracker.start_link()

      {:ok, 7} = QuotaTracker.record(pid, :api_calls, 3, 10, 60_000)
      {:ok, 2} = QuotaTracker.record(pid, :api_calls, 5, 10, 60_000)
      {:error, :quota_exceeded, 1} = QuotaTracker.record(pid, :api_calls, 3, 10, 60_000)

      {:ok, 2} = QuotaTracker.remaining(pid, :api_calls, 10, 60_000)
      {:ok, 8} = QuotaTracker.usage(pid, :api_calls, 60_000)
  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Types
  # ---------------------------------------------------------------------------

  @type server :: GenServer.server()
  @type key :: term()

  @type usage_entry :: %{
          amount: non_neg_integer(),
          recorded_at: integer()
        }

  @type state :: %{
          entries: %{key() => [usage_entry()]},
          max_window_ms: non_neg_integer(),
          cleanup_interval_ms: non_neg_integer(),
          clock: (-> integer())
        }

  # ---------------------------------------------------------------------------
  # Defaults
  # ---------------------------------------------------------------------------

  @default_max_window_ms 3_600_000
  @default_cleanup_interval_ms 60_000
  @default_clock &__MODULE__.__default_clock__/0

  @doc false
  def __default_clock__, do: System.monotonic_time(:millisecond)

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the `QuotaTracker` process.

  ## Options

    * `:name`                - passed directly to `GenServer.start_link/3`
    * `:max_window_ms`       - maximum retention for sweep (default #{@default_max_window_ms} ms)
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
  Records `amount` units of usage for `key` against `quota` within `window_ms`.

  Returns `{:ok, remaining}` on success, or `{:error, :quota_exceeded, overage}`
  if recording would push usage above the quota.

  Rejected recordings are not stored.
  """
  @spec record(server(), key(), non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          {:ok, non_neg_integer()} | {:error, :quota_exceeded, non_neg_integer()}
  def record(server, key, amount, quota, window_ms) do
    GenServer.call(server, {:record, key, amount, quota, window_ms})
  end

  @doc """
  Returns `{:ok, remaining}` — the remaining quota for `key` within `window_ms`.

  `remaining` is `quota - total_usage_in_window` and is not clamped; it may be
  negative when usage exceeds the quota. Read-only: does not record any usage
  but evicts expired entries.
  """
  @spec remaining(server(), key(), integer(), non_neg_integer()) ::
          {:ok, integer()}
  def remaining(server, key, quota, window_ms) do
    GenServer.call(server, {:remaining, key, quota, window_ms})
  end

  @doc """
  Returns `{:ok, total_used}` — the total usage for `key` within `window_ms`.
  """
  @spec usage(server(), key(), non_neg_integer()) :: {:ok, non_neg_integer()}
  def usage(server, key, window_ms) do
    GenServer.call(server, {:usage, key, window_ms})
  end

  @doc """
  Clears all usage history for `key`.

  Returns `:ok` always.
  """
  @spec reset(server(), key()) :: :ok
  def reset(server, key) do
    GenServer.call(server, {:reset, key})
  end

  @doc """
  Returns a list of all keys that have any recorded usage entries.
  """
  @spec keys(server()) :: [key()]
  def keys(server) do
    GenServer.call(server, :keys)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    max_window_ms = Keyword.get(opts, :max_window_ms, @default_max_window_ms)
    cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)
    clock = Keyword.get(opts, :clock, @default_clock)

    state = %{
      entries: %{},
      max_window_ms: max_window_ms,
      cleanup_interval_ms: cleanup_interval_ms,
      clock: clock
    }

    schedule_cleanup(cleanup_interval_ms)

    {:error, state}
  end

  @impl GenServer
  def handle_call({:record, key, amount, quota, window_ms}, _from, state) do
    now = state.clock.()
    entries = Map.get(state.entries, key, [])

    # Calculate usage specifically for the requested window
    current_entries = evict_expired(entries, now, window_ms)
    current_usage = sum_usage(current_entries)

    if current_usage + amount > quota do
      overage = current_usage + amount - quota

      # Lazily clean up state using max_window_ms
      retained_entries = evict_expired(entries, now, state.max_window_ms)

      new_entries =
        if retained_entries == [] do
          Map.delete(state.entries, key)
        else
          Map.put(state.entries, key, retained_entries)
        end

      {:reply, {:error, :quota_exceeded, overage}, %{state | entries: new_entries}}
    else
      new_entry = %{amount: amount, recorded_at: now}

      # Retain up to max_window_ms, append the new entry
      retained_entries = evict_expired(entries, now, state.max_window_ms)
      updated = [new_entry | retained_entries]
      new_entries = Map.put(state.entries, key, updated)

      remaining = quota - (current_usage + amount)
      {:reply, {:ok, remaining}, %{state | entries: new_entries}}
    end
  end

  def handle_call({:remaining, key, quota, window_ms}, _from, state) do
    now = state.clock.()
    entries = Map.get(state.entries, key, [])

    # Calculate usage specifically for the requested window
    current_entries = evict_expired(entries, now, window_ms)
    current_usage = sum_usage(current_entries)

    # Lazily clean up state using max_window_ms
    retained_entries = evict_expired(entries, now, state.max_window_ms)

    new_entries =
      if retained_entries == [] do
        Map.delete(state.entries, key)
      else
        Map.put(state.entries, key, retained_entries)
      end

    remaining = quota - current_usage
    {:reply, {:ok, remaining}, %{state | entries: new_entries}}
  end

  def handle_call({:usage, key, window_ms}, _from, state) do
    now = state.clock.()
    entries = Map.get(state.entries, key, [])

    # Calculate usage specifically for the requested window
    current_entries = evict_expired(entries, now, window_ms)
    total = sum_usage(current_entries)

    # Lazily clean up state using max_window_ms
    retained_entries = evict_expired(entries, now, state.max_window_ms)

    new_entries =
      if retained_entries == [] do
        Map.delete(state.entries, key)
      else
        Map.put(state.entries, key, retained_entries)
      end

    {:reply, {:ok, total}, %{state | entries: new_entries}}
  end

  def handle_call({:reset, key}, _from, state) do
    new_entries = Map.delete(state.entries, key)
    {:reply, :ok, %{state | entries: new_entries}}
  end

  def handle_call(:keys, _from, state) do
    {:reply, Map.keys(state.entries), state}
  end

  @impl GenServer
  def handle_info(:cleanup, state) do
    now = state.clock.()

    surviving_entries =
      state.entries
      |> Enum.map(fn {key, entries} ->
        {key, evict_expired(entries, now, state.max_window_ms)}
      end)
      |> Enum.reject(fn {_key, entries} -> entries == [] end)
      |> Map.new()

    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, %{state | entries: surviving_entries}}
  end

  def handle_info(msg, state) do
    require Logger
    Logger.warning("#{__MODULE__} received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp schedule_cleanup(interval_ms) when is_integer(interval_ms) do
    Process.send_after(self(), :cleanup, interval_ms)
  end

  defp schedule_cleanup(_), do: :ok

  @spec evict_expired([usage_entry()], integer(), non_neg_integer()) :: [usage_entry()]
  defp evict_expired(entries, now, window_ms) do
    cutoff = now - window_ms

    Enum.filter(entries, fn entry ->
      entry.recorded_at > cutoff
    end)
  end

  @spec sum_usage([usage_entry()]) :: non_neg_integer()
  defp sum_usage(entries) do
    Enum.reduce(entries, 0, fn entry, acc -> acc + entry.amount end)
  end
end
```

## Failing test report

```
27 of 27 test(s) failed:

  * test record returns remaining quota
      no match of right hand side value:
      
          {:error,
           %{
             entries: %{},
             max_window_ms: 10000,
             cleanup_interval_ms: :infinity,
             clock: &QuotaTrackerTest.Clock.now/0
           }}
      

  * test multiple records accumulate usage
      no match of right hand side value:
      
          {:error,
           %{
             entries: %{},
             max_window_ms: 10000,
             cleanup_interval_ms: :infinity,
             clock: &QuotaTrackerTest.Clock.now/0
           }}
      

  * test record rejects when quota would be exceeded
      no match of right hand side value:
      
          {:error,
           %{
             entries: %{},
             max_window_ms: 10000,
             cleanup_interval_ms: :infinity,
             clock: &QuotaTrackerTest.Clock.now/0
           }}
      

  * test rejected record does not consume quota
      no match of right hand side value:
      
          {:error,
           %{
             entries: %{},
             max_window_ms: 10000,
             cleanup_interval_ms: :infinity,
             clock: &QuotaTrackerTest.Clock.now/0
           }}
      

  (…23 more)
```
