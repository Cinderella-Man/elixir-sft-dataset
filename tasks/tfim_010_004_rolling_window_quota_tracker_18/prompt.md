# One test is missing its body

Module plus harness below; a single `test` body was replaced with
`# TODO`. Reconstruct it from its name and the surrounding suite so the
harness passes for a correct implementation of the module. Touch nothing
else.

## Module under test

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

    {:ok, state}
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

## Test harness — implement the `# TODO` test

```elixir
defmodule QuotaTrackerTest do
  use ExUnit.Case, async: false

  # --- Fake clock for deterministic testing ---

  defmodule Clock do
    use Agent

    def start_link(initial \\ 0) do
      Agent.start_link(fn -> initial end, name: __MODULE__)
    end

    def now, do: Agent.get(__MODULE__, & &1)
    def advance(ms), do: Agent.update(__MODULE__, &(&1 + ms))
    def set(ms), do: Agent.update(__MODULE__, fn _ -> ms end)
  end

  setup do
    start_supervised!({Clock, 0})

    {:ok, pid} =
      QuotaTracker.start_link(
        clock: &Clock.now/0,
        max_window_ms: 10_000,
        cleanup_interval_ms: :infinity
      )

    %{tracker: pid}
  end

  # -------------------------------------------------------
  # Basic record / remaining / usage
  # -------------------------------------------------------

  test "record returns remaining quota", %{tracker: t} do
    assert {:ok, 7} = QuotaTracker.record(t, :api, 3, 10, 1_000)
  end

  test "multiple records accumulate usage", %{tracker: t} do
    assert {:ok, 7} = QuotaTracker.record(t, :api, 3, 10, 1_000)
    assert {:ok, 2} = QuotaTracker.record(t, :api, 5, 10, 1_000)
  end

  test "record rejects when quota would be exceeded", %{tracker: t} do
    {:ok, _} = QuotaTracker.record(t, :api, 8, 10, 1_000)

    assert {:error, :quota_exceeded, 1} = QuotaTracker.record(t, :api, 3, 10, 1_000)
  end

  test "rejected record does not consume quota", %{tracker: t} do
    {:ok, _} = QuotaTracker.record(t, :api, 8, 10, 1_000)
    {:error, :quota_exceeded, _} = QuotaTracker.record(t, :api, 5, 10, 1_000)

    # Only the first 8 should be recorded
    assert {:ok, 2} = QuotaTracker.remaining(t, :api, 10, 1_000)
  end

  test "remaining returns full quota for unknown key", %{tracker: t} do
    assert {:ok, 100} = QuotaTracker.remaining(t, :unknown, 100, 1_000)
  end

  test "usage returns 0 for unknown key", %{tracker: t} do
    assert {:ok, 0} = QuotaTracker.usage(t, :unknown, 1_000)
  end

  test "usage returns total for known key", %{tracker: t} do
    {:ok, _} = QuotaTracker.record(t, :api, 3, 10, 1_000)
    {:ok, _} = QuotaTracker.record(t, :api, 5, 10, 1_000)

    assert {:ok, 8} = QuotaTracker.usage(t, :api, 1_000)
  end

  # -------------------------------------------------------
  # Rolling window expiration
  # -------------------------------------------------------

  test "usage entries expire after window", %{tracker: t} do
    {:ok, _} = QuotaTracker.record(t, :api, 5, 10, 1_000)

    Clock.advance(1_001)

    assert {:ok, 0} = QuotaTracker.usage(t, :api, 1_000)
    assert {:ok, 10} = QuotaTracker.remaining(t, :api, 10, 1_000)
  end

  test "expired usage frees quota for new records", %{tracker: t} do
    {:ok, _} = QuotaTracker.record(t, :api, 10, 10, 1_000)
    {:error, :quota_exceeded, _} = QuotaTracker.record(t, :api, 1, 10, 1_000)

    Clock.advance(1_001)

    assert {:ok, 5} = QuotaTracker.record(t, :api, 5, 10, 1_000)
  end

  test "entries within window are kept, expired entries are dropped", %{tracker: t} do
    {:ok, _} = QuotaTracker.record(t, :api, 3, 10, 1_000)

    Clock.advance(500)
    {:ok, _} = QuotaTracker.record(t, :api, 4, 10, 1_000)

    # At 1001ms: first record (at t=0) expires, second (at t=500) still live
    Clock.advance(501)

    assert {:ok, 4} = QuotaTracker.usage(t, :api, 1_000)
    assert {:ok, 6} = QuotaTracker.remaining(t, :api, 10, 1_000)
  end

  # -------------------------------------------------------
  # Reset
  # -------------------------------------------------------

  test "reset clears all usage for a key", %{tracker: t} do
    {:ok, _} = QuotaTracker.record(t, :api, 8, 10, 1_000)

    assert :ok = QuotaTracker.reset(t, :api)
    assert {:ok, 0} = QuotaTracker.usage(t, :api, 1_000)
    assert {:ok, 10} = QuotaTracker.remaining(t, :api, 10, 1_000)
  end

  test "reset returns :ok for unknown key", %{tracker: t} do
    assert :ok = QuotaTracker.reset(t, :nonexistent)
  end

  test "record works normally after reset", %{tracker: t} do
    {:ok, _} = QuotaTracker.record(t, :api, 10, 10, 1_000)
    QuotaTracker.reset(t, :api)

    assert {:ok, 5} = QuotaTracker.record(t, :api, 5, 10, 1_000)
  end

  # -------------------------------------------------------
  # Key independence
  # -------------------------------------------------------

  test "keys track usage independently", %{tracker: t} do
    {:ok, _} = QuotaTracker.record(t, :api, 8, 10, 1_000)
    {:ok, _} = QuotaTracker.record(t, :uploads, 3, 5, 1_000)

    assert {:ok, 8} = QuotaTracker.usage(t, :api, 1_000)
    assert {:ok, 3} = QuotaTracker.usage(t, :uploads, 1_000)
    assert {:ok, 2} = QuotaTracker.remaining(t, :api, 10, 1_000)
    assert {:ok, 2} = QuotaTracker.remaining(t, :uploads, 5, 1_000)
  end

  test "resetting one key does not affect another", %{tracker: t} do
    {:ok, _} = QuotaTracker.record(t, :api, 5, 10, 1_000)
    {:ok, _} = QuotaTracker.record(t, :uploads, 3, 5, 1_000)

    QuotaTracker.reset(t, :api)

    assert {:ok, 0} = QuotaTracker.usage(t, :api, 1_000)
    assert {:ok, 3} = QuotaTracker.usage(t, :uploads, 1_000)
  end

  # -------------------------------------------------------
  # Keys listing
  # -------------------------------------------------------

  test "keys returns all tracked keys", %{tracker: t} do
    {:ok, _} = QuotaTracker.record(t, :api, 1, 10, 1_000)
    {:ok, _} = QuotaTracker.record(t, :uploads, 1, 10, 1_000)
    {:ok, _} = QuotaTracker.record(t, :downloads, 1, 10, 1_000)

    keys = QuotaTracker.keys(t)
    assert Enum.sort(keys) == [:api, :downloads, :uploads]
  end

  # -------------------------------------------------------
  # Exact boundary behavior
  # -------------------------------------------------------

  test "record at exact quota boundary succeeds", %{tracker: t} do
    # TODO
  end

  test "record of 1 over quota fails", %{tracker: t} do
    {:ok, _} = QuotaTracker.record(t, :api, 10, 10, 1_000)
    assert {:error, :quota_exceeded, 1} = QuotaTracker.record(t, :api, 1, 10, 1_000)
  end

  # -------------------------------------------------------
  # Cleanup (memory leak prevention)
  # -------------------------------------------------------

  test "expired entries are cleaned up by sweep", %{tracker: t} do
    for i <- 1..50 do
      {:ok, _} = QuotaTracker.record(t, "key_#{i}", 1, 100, 1_000)
    end

    Clock.advance(10_001)

    send(t, :cleanup)

    # keys/1 is a GenServer call, so it is processed after the :cleanup
    # message and also confirms the sweep did not crash the server. The sweep
    # removes keys whose usage lists are empty after eviction, and every entry
    # here is older than max_window_ms, so no keys may remain. Internal state
    # is deliberately not inspected.
    assert QuotaTracker.keys(t) == []
    assert Process.alive?(t)
  end

  test "cleanup only removes fully expired keys, keeps active ones", %{tracker: t} do
    {:ok, _} = QuotaTracker.record(t, :old, 5, 10, 1_000)

    Clock.advance(9_000)
    {:ok, _} = QuotaTracker.record(t, :new, 3, 10, 1_000)

    Clock.advance(1_001)

    send(t, :cleanup)

    # keys/1 is a GenServer call, so it is processed after the :cleanup
    # message and also confirms the sweep did not crash the server. :old's
    # only entry (age 10_001ms) is past max_window_ms and must be swept away;
    # :new's entry (age 1_001ms) is within max_window_ms and must survive the
    # sweep even though it is outside its own 1_000ms query window. Internal
    # state is deliberately not inspected.
    assert QuotaTracker.keys(t) == [:new]
    assert Process.alive?(t)
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "different window sizes on same key", %{tracker: t} do
    {:ok, _} = QuotaTracker.record(t, :api, 5, 100, 2_000)

    Clock.advance(1_500)
    {:ok, _} = QuotaTracker.record(t, :api, 3, 100, 2_000)

    # With a 1000ms window, only the second record (at t=1500) is visible
    assert {:ok, 3} = QuotaTracker.usage(t, :api, 1_000)

    # With a 2000ms window, both records are visible
    assert {:ok, 8} = QuotaTracker.usage(t, :api, 2_000)
  end

  test "record with amount 0 succeeds without affecting quota", %{tracker: t} do
    assert {:ok, 10} = QuotaTracker.record(t, :api, 0, 10, 1_000)
    assert {:ok, 0} = QuotaTracker.usage(t, :api, 1_000)
  end

  test "keys lists a key whose entries have all aged past the query window",
       %{tracker: t} do
    {:ok, _} = QuotaTracker.record(t, :api, 5, 10, 1_000)

    Clock.advance(5_000)

    # The entry is far outside its 1_000ms query window (so usage reads 0) yet
    # still within max_window_ms (10_000), so keys/1 must still list the key.
    assert {:ok, 0} = QuotaTracker.usage(t, :api, 1_000)
    assert QuotaTracker.keys(t) == [:api]
  end

  test "remaining reports negative headroom when usage exceeds the quota",
       %{tracker: t} do
    {:ok, _} = QuotaTracker.record(t, :api, 8, 10, 1_000)

    # 8 units are counted in the window; against a quota of 5 the promised
    # value is 5 - 8 = -3 (the formula is stated with no clamping).
    assert {:ok, -3} = QuotaTracker.remaining(t, :api, 5, 1_000)
  end

  test "default max_window_ms evicts entries after one hour" do
    {:ok, t2} =
      QuotaTracker.start_link(clock: &Clock.now/0, cleanup_interval_ms: :infinity)

    {:ok, _} = QuotaTracker.record(t2, :api, 5, 10, 1_000)

    # Just under the default hour: lazy cleanup on access must retain the entry.
    Clock.advance(3_599_999)
    {:ok, _} = QuotaTracker.usage(t2, :api, 100_000_000)
    assert QuotaTracker.keys(t2) == [:api]

    # At the default hour: lazy cleanup on access must evict, dropping the key.
    Clock.advance(1)
    {:ok, _} = QuotaTracker.usage(t2, :api, 100_000_000)
    assert QuotaTracker.keys(t2) == []
  end

  test "name option registers the process for lookups" do
    {:ok, _pid} =
      QuotaTracker.start_link(
        name: :quota_tracker_named,
        clock: &Clock.now/0,
        cleanup_interval_ms: :infinity
      )

    assert {:ok, 7} = QuotaTracker.record(:quota_tracker_named, :api, 3, 10, 1_000)
    assert {:ok, 3} = QuotaTracker.usage(:quota_tracker_named, :api, 1_000)
  end

  test "reset removes the key from the keys listing", %{tracker: t} do
    {:ok, _} = QuotaTracker.record(t, :api, 5, 10, 1_000)
    {:ok, _} = QuotaTracker.record(t, :uploads, 3, 10, 1_000)

    :ok = QuotaTracker.reset(t, :api)

    assert QuotaTracker.keys(t) == [:uploads]
  end

  # -------------------------------------------------------
  # The periodic cleanup is driven by an automatically scheduled timer
  # -------------------------------------------------------

  test "the periodic cleanup timer fires and re-arms automatically" do
    test_pid = self()

    # Every cleanup pass reads the clock. This probe records each such call;
    # no other API call is issued after startup, so each tick is an automatic
    # sweep.
    clock = fn ->
      send(test_pid, :cleanup_clock_tick)
      0
    end

    {:ok, _pid} =
      QuotaTracker.start_link(max_window_ms: 10_000, clock: clock, cleanup_interval_ms: 25)

    # The first tick proves the startup timer fired; the second proves the pass
    # re-armed the next one, so the sweep repeats rather than running just once.
    # A scheduler that never arms Process.send_after would produce no ticks.
    assert_receive :cleanup_clock_tick, 1_000
    assert_receive :cleanup_clock_tick, 1_000
  end
end
```
