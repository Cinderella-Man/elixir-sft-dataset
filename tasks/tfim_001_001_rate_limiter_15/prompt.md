# One test is missing its body

Module plus harness below; a single `test` body was replaced with
`# TODO`. Reconstruct it from its name and the surrounding suite so the
harness passes for a correct implementation of the module. Touch nothing
else.

## Module under test

```elixir
defmodule RateLimiter do
  @moduledoc """
  A GenServer that enforces per-key rate limits using a sliding window algorithm.

  Each key is tracked independently via a list of request timestamps.
  On every `check/4` call, timestamps outside the current window are pruned,
  and the request is allowed only if the remaining count is within the limit.

  Expired entries are garbage-collected on a configurable periodic sweep so the
  process never leaks memory for keys that stop receiving traffic.

  ## Options

    * `:name`                 – process registration name (optional)
    * `:clock`                – zero-arity function returning current time in ms
                                (default: `fn -> System.monotonic_time(:millisecond) end`)
    * `:cleanup_interval_ms`  – how often the periodic sweep runs in ms (default: 60_000)

  ## Examples

      iex> {:ok, pid} = RateLimiter.start_link([])
      iex> {:ok, 4} = RateLimiter.check(pid, "user:1", 5, 1_000)
      iex> {:ok, 3} = RateLimiter.check(pid, "user:1", 5, 1_000)

  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the RateLimiter process and links it to the caller.

  ## Options

    * `:name`                 – optional registered name
    * `:clock`                – `(-> integer())` returning now in milliseconds
    * `:cleanup_interval_ms`  – sweep interval (default `60_000`)

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)

    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Checks whether a request for `key` is allowed under the given limits.

  Returns `{:ok, remaining}` when the request is accepted, where `remaining`
  is the number of additional requests the caller may make in this window.

  Returns `{:error, :rate_limited, retry_after_ms}` when the limit has been
  reached.  `retry_after_ms` is the minimum wait (in milliseconds) before the
  oldest tracked request falls outside the window.
  """
  @spec check(GenServer.server(), term(), pos_integer(), pos_integer()) ::
          {:ok, non_neg_integer()} | {:error, :rate_limited, non_neg_integer()}
  def check(server, key, max_requests, window_ms)
      when is_integer(max_requests) and max_requests > 0 and
             is_integer(window_ms) and window_ms > 0 do
    GenServer.call(server, {:check, key, max_requests, window_ms})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @default_cleanup_interval_ms 60_000

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    cleanup_interval = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)

    schedule_cleanup(cleanup_interval)

    {:ok,
     %{
       # %{key => {[timestamp], window_ms}}
       keys: %{},
       clock: clock,
       cleanup_interval_ms: cleanup_interval
     }}
  end

  @impl true
  def handle_call({:check, key, max_requests, window_ms}, _from, state) do
    now = state.clock.()

    # Fetch existing timestamps for this key (or empty list).
    {timestamps, _old_window} = Map.get(state.keys, key, {[], window_ms})

    # Prune timestamps that have fallen outside the sliding window.
    window_start = now - window_ms
    active = Enum.filter(timestamps, fn ts -> ts > window_start end)

    count = length(active)

    if count < max_requests do
      # Allow the request – record its timestamp.
      updated = [now | active]
      remaining = max_requests - count - 1

      new_keys = Map.put(state.keys, key, {updated, window_ms})
      {:reply, {:ok, remaining}, %{state | keys: new_keys}}
    else
      # Denied – compute how long until the oldest active entry expires.
      oldest = List.last(active)
      retry_after = oldest + window_ms - now
      retry_after = max(retry_after, 1)

      # Update state with the pruned list even on failure
      new_state = put_in(state.keys[key], {active, window_ms})

      {:reply, {:error, :rate_limited, retry_after}, new_state}
    end
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = state.clock.()

    cleaned =
      state.keys
      |> Enum.reduce(%{}, fn {key, {timestamps, window_ms}}, acc ->
        window_start = now - window_ms
        active = Enum.filter(timestamps, fn ts -> ts > window_start end)

        # Drop the key entirely when no active timestamps remain.
        if active == [] do
          acc
        else
          Map.put(acc, key, {active, window_ms})
        end
      end)

    schedule_cleanup(state.cleanup_interval_ms)

    {:noreply, %{state | keys: cleaned}}
  end

  # Catch-all so unexpected messages don't crash the process.
  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp schedule_cleanup(:infinity), do: :ok

  defp schedule_cleanup(interval_ms) when is_integer(interval_ms) do
    Process.send_after(self(), :cleanup, interval_ms)
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule RateLimiterTest do
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
    # Start fresh clock at time 0 for each test
    start_supervised!({Clock, 0})

    {:ok, pid} =
      RateLimiter.start_link(
        clock: &Clock.now/0,
        # disable auto-cleanup in tests
        cleanup_interval_ms: :infinity
      )

    %{rl: pid}
  end

  # -------------------------------------------------------
  # Basic allow / reject
  # -------------------------------------------------------

  test "allows requests within the limit", %{rl: rl} do
    assert {:ok, 2} = RateLimiter.check(rl, "user:1", 3, 1_000)
    assert {:ok, 1} = RateLimiter.check(rl, "user:1", 3, 1_000)
    assert {:ok, 0} = RateLimiter.check(rl, "user:1", 3, 1_000)
  end

  test "rejects the request that exceeds the limit", %{rl: rl} do
    for _ <- 1..3, do: RateLimiter.check(rl, "k", 3, 1_000)

    assert {:error, :rate_limited, retry_after} =
             RateLimiter.check(rl, "k", 3, 1_000)

    assert is_integer(retry_after)
    assert retry_after > 0
    assert retry_after <= 1_000
  end

  # -------------------------------------------------------
  # Window sliding
  # -------------------------------------------------------

  test "allows requests again after the window slides", %{rl: rl} do
    for _ <- 1..3, do: RateLimiter.check(rl, "k", 3, 1_000)
    assert {:error, :rate_limited, _} = RateLimiter.check(rl, "k", 3, 1_000)

    # Advance past the window
    Clock.advance(1_001)

    assert {:ok, _remaining} = RateLimiter.check(rl, "k", 3, 1_000)
  end

  test "sliding window drops old requests correctly", %{rl: rl} do
    # Time 0: first request
    assert {:ok, 2} = RateLimiter.check(rl, "k", 3, 1_000)

    # Time 400: second request
    Clock.advance(400)
    assert {:ok, 1} = RateLimiter.check(rl, "k", 3, 1_000)

    # Time 800: third request
    Clock.advance(400)
    assert {:ok, 0} = RateLimiter.check(rl, "k", 3, 1_000)

    # Time 800: fourth request — rejected
    assert {:error, :rate_limited, _} = RateLimiter.check(rl, "k", 3, 1_000)

    # Time 1001: first request (from time 0) has expired, one slot free
    Clock.advance(201)
    assert {:ok, 0} = RateLimiter.check(rl, "k", 3, 1_000)

    # Still blocked (requests from 400 and 800 still in window)
    assert {:error, :rate_limited, _} = RateLimiter.check(rl, "k", 3, 1_000)
  end

  # -------------------------------------------------------
  # Key independence
  # -------------------------------------------------------

  test "different keys are completely independent", %{rl: rl} do
    # Exhaust key "a"
    for _ <- 1..3, do: RateLimiter.check(rl, "a", 3, 1_000)
    assert {:error, :rate_limited, _} = RateLimiter.check(rl, "a", 3, 1_000)

    # Key "b" should be unaffected
    assert {:ok, 2} = RateLimiter.check(rl, "b", 3, 1_000)
    assert {:ok, 1} = RateLimiter.check(rl, "b", 3, 1_000)
    assert {:ok, 0} = RateLimiter.check(rl, "b", 3, 1_000)
  end

  # -------------------------------------------------------
  # retry_after accuracy
  # -------------------------------------------------------

  test "retry_after tells the caller how long until a slot opens", %{rl: rl} do
    # Request at time 0
    RateLimiter.check(rl, "k", 1, 1_000)

    # Advance to time 300
    Clock.advance(300)

    assert {:error, :rate_limited, retry_after} =
             RateLimiter.check(rl, "k", 1, 1_000)

    # The earliest request (at time 0) expires at time 1000.
    # We're at time 300, so retry_after should be ~700
    assert retry_after >= 600 and retry_after <= 800
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "max_requests of 1 allows exactly one call", %{rl: rl} do
    assert {:ok, 0} = RateLimiter.check(rl, "k", 1, 500)
    assert {:error, :rate_limited, _} = RateLimiter.check(rl, "k", 1, 500)
  end

  test "works with very large window", %{rl: rl} do
    assert {:ok, 0} = RateLimiter.check(rl, "k", 1, 86_400_000)
    assert {:error, :rate_limited, _} = RateLimiter.check(rl, "k", 1, 86_400_000)

    Clock.advance(86_400_001)
    assert {:ok, 0} = RateLimiter.check(rl, "k", 1, 86_400_000)
  end

  # -------------------------------------------------------
  # Multiple keys interleaved
  # -------------------------------------------------------

  test "interleaved operations on multiple keys", %{rl: rl} do
    assert {:ok, 1} = RateLimiter.check(rl, "x", 2, 1_000)
    assert {:ok, 4} = RateLimiter.check(rl, "y", 5, 2_000)
    assert {:ok, 0} = RateLimiter.check(rl, "x", 2, 1_000)
    assert {:ok, 3} = RateLimiter.check(rl, "y", 5, 2_000)

    assert {:error, :rate_limited, _} = RateLimiter.check(rl, "x", 2, 1_000)
    assert {:ok, 2} = RateLimiter.check(rl, "y", 5, 2_000)
  end

  # -------------------------------------------------------
  # Cleanup (memory leak prevention)
  # -------------------------------------------------------

  test "expired keys are cleaned up and don't accumulate", %{rl: rl} do
    # Create entries for 100 different keys
    for i <- 1..100 do
      RateLimiter.check(rl, "key:#{i}", 1, 100)
    end

    # Advance past all windows
    Clock.advance(200)

    # Trigger the sweep manually via the documented :cleanup message
    send(rl, :cleanup)

    # A GenServer processes its mailbox in order, so the calls below also
    # confirm the sweep finished without crashing the server. Internal state
    # is implementation-dependent and deliberately not inspected; the
    # observable contract is that previously tracked keys start a fresh
    # window after expiry (remaining = max - 1).
    assert {:ok, 0} = RateLimiter.check(rl, "key:1", 1, 100)
    assert {:ok, 0} = RateLimiter.check(rl, "key:100", 1, 100)
    assert Process.alive?(rl)
  end

  # -------------------------------------------------------
  # Window boundary is exclusive: ts is active iff ts > now - window_ms
  # -------------------------------------------------------

  test "an entry exactly window_ms old is no longer active", %{rl: rl} do
    # Three calls at time 0 exhaust the limit.
    assert {:ok, 2} = RateLimiter.check(rl, "k", 3, 1_000)
    assert {:ok, 1} = RateLimiter.check(rl, "k", 3, 1_000)
    assert {:ok, 0} = RateLimiter.check(rl, "k", 3, 1_000)
    assert {:error, :rate_limited, 1_000} = RateLimiter.check(rl, "k", 3, 1_000)

    # At exactly time 1000 the time-0 entries have fallen out of the window
    # (0 > 1000 - 1000 is false), so the window is empty again.
    Clock.advance(1_000)
    assert {:ok, 2} = RateLimiter.check(rl, "k", 3, 1_000)
  end

  # -------------------------------------------------------
  # retry_after is exact, and waiting exactly that long works
  # -------------------------------------------------------

  test "retry_after is the exact wait until the oldest entry expires", %{rl: rl} do
    # Single request at time 0 under a limit of 1 per 1000ms.
    assert {:ok, 0} = RateLimiter.check(rl, "k", 1, 1_000)

    # At time 999 the entry expires in exactly 1ms: max(0 + 1000 - 999, 1) == 1.
    Clock.advance(999)
    assert {:error, :rate_limited, 1} = RateLimiter.check(rl, "k", 1, 1_000)

    # Waiting exactly retry_after_ms must succeed (no calls in between; a denied
    # call records no timestamp, so the window did not move forward).
    Clock.advance(1)
    assert {:ok, 0} = RateLimiter.check(rl, "k", 1, 1_000)
  end

  # -------------------------------------------------------
  # Argument guards on check/4
  # -------------------------------------------------------

  test "check/4 guards reject non-positive limits but accept 1", %{rl: rl} do
    assert_raise FunctionClauseError, fn ->
      RateLimiter.check(rl, "k", 0, 1_000)
    end

    assert_raise FunctionClauseError, fn ->
      RateLimiter.check(rl, "k", 1, 0)
    end

    # 1 is a positive integer and must be inside the contract for both args.
    assert {:ok, 0} = RateLimiter.check(rl, "k", 1, 1)
    assert Process.alive?(rl)
  end

  # -------------------------------------------------------
  # Cleanup drops keys at the same exclusive boundary check/4 uses
  # -------------------------------------------------------

  test "cleanup removes a key whose entries are exactly window_ms old", %{rl: rl} do
    # TODO
  end

  test "check/4 works through the registered name and the pid alike" do
    name = :rate_limiter_registered_name_test

    {:ok, pid} =
      RateLimiter.start_link(
        name: name,
        clock: &Clock.now/0,
        cleanup_interval_ms: :infinity
      )

    # Same process reached two ways: state accumulates across both call styles.
    assert {:ok, 4} = RateLimiter.check(name, "u", 5, 1_000)
    assert {:ok, 3} = RateLimiter.check(pid, "u", 5, 1_000)
  end

  test "repeated denials never postpone when the original entry frees a slot", %{rl: rl} do
    # One request at time 0 exhausts a limit of 1 per 1000ms.
    assert {:ok, 0} = RateLimiter.check(rl, "k", 1, 1_000)

    # Hammer the limited key twice while blocked; neither denial records a ts.
    Clock.advance(500)
    assert {:error, :rate_limited, 500} = RateLimiter.check(rl, "k", 1, 1_000)
    Clock.advance(400)
    assert {:error, :rate_limited, 100} = RateLimiter.check(rl, "k", 1, 1_000)

    # At time 1000 only the time-0 entry mattered; the hammering did not push
    # its expiry forward, so a slot is free.
    Clock.advance(100)
    assert {:ok, 0} = RateLimiter.check(rl, "k", 1, 1_000)
  end

  test "cleanup reclaims an expired entry before a wider-window check", %{rl: rl} do
    # Record a request at time 0 under a 1000ms window (stored window = 1000).
    assert {:ok, 0} = RateLimiter.check(rl, "k", 1, 1_000)

    Clock.advance(1_500)

    # A cleanup pass prunes using the key's last-seen 1000ms window. At time 1500
    # the time-0 entry is not active for that window (0 > 1500 - 1000 is false),
    # so the key's active list becomes empty and the key is removed entirely —
    # exactly the memory-reclamation the cleanup contract mandates.
    send(rl, :cleanup)

    # The reclaimed key now behaves exactly like a never-seen key: even a wider
    # 2000ms window starts a fresh window rather than resurrecting the pruned
    # entry, so the first call must be allowed with remaining = max - 1.
    assert {:ok, 0} = RateLimiter.check(rl, "k", 1, 2_000)
  end

  test "cleanup keeps a key that still has an active timestamp", %{rl: rl} do
    assert {:ok, 1} = RateLimiter.check(rl, "k", 2, 1_000)
    Clock.advance(600)
    assert {:ok, 0} = RateLimiter.check(rl, "k", 2, 1_000)

    # Time 1100: the time-0 entry falls out, the time-600 entry stays active.
    Clock.advance(500)
    send(rl, :cleanup)

    # The retained (pruned) list still holds the time-600 entry, so a limit of 1
    # must be denied — a wrongly dropped key would return {:ok, 0} here.
    assert {:error, :rate_limited, 500} = RateLimiter.check(rl, "k", 1, 1_000)
  end

  test "an unexpected message leaves tracking state untouched", %{rl: rl} do
    assert {:ok, 1} = RateLimiter.check(rl, "k", 2, 1_000)

    send(rl, :some_unexpected_message)
    send(rl, {:weird, :tuple, 123})

    # State unaltered: the earlier request still counts toward the limit.
    assert {:ok, 0} = RateLimiter.check(rl, "k", 2, 1_000)
    assert {:error, :rate_limited, _} = RateLimiter.check(rl, "k", 2, 1_000)
    assert Process.alive?(rl)
  end

  test "cleanup on a fresh empty state is a harmless no-op", %{rl: rl} do
    send(rl, :cleanup)
    send(rl, :cleanup)

    # An untouched key still behaves like a brand-new key after empty sweeps.
    assert {:ok, 4} = RateLimiter.check(rl, "brand:new", 5, 1_000)
    assert Process.alive?(rl)
  end

  test "keys are compared by value across term types", %{rl: rl} do
    # A tuple key and an equal tuple share one bucket (compared by value).
    assert {:ok, 1} = RateLimiter.check(rl, {:user, 1}, 2, 1_000)
    assert {:ok, 0} = RateLimiter.check(rl, {:user, 1}, 2, 1_000)
    assert {:error, :rate_limited, _} = RateLimiter.check(rl, {:user, 1}, 2, 1_000)

    # An integer key and an atom key are independent from the tuple and each other.
    assert {:ok, 1} = RateLimiter.check(rl, 42, 2, 1_000)
    assert {:ok, 1} = RateLimiter.check(rl, :admin, 2, 1_000)

    # A different-valued tuple is its own bucket, unaffected by the exhausted one.
    assert {:ok, 1} = RateLimiter.check(rl, {:user, 2}, 2, 1_000)
  end

  test "pruning uses the window_ms of the current call not a stored one", %{rl: rl} do
    # Record one timestamp at time 0 under a 1000ms window.
    assert {:ok, 0} = RateLimiter.check(rl, "k", 1, 1_000)

    # At time 600 a check with a narrower 500ms window prunes the time-0 entry
    # (0 > 600 - 500 is false), so the request must be allowed. Had the stored
    # 1000ms window governed, the entry would still be active and this would deny.
    Clock.advance(600)
    assert {:ok, 0} = RateLimiter.check(rl, "k", 1, 500)
  end

  test "cleanup prunes using the most recently seen window for a key", %{rl: rl} do
    # First seen with a narrow 500ms window at time 0.
    assert {:ok, 1} = RateLimiter.check(rl, "k", 2, 500)

    # Re-seen with a much wider 5000ms window at time 100; stored window becomes 5000.
    Clock.advance(100)
    assert {:ok, 0} = RateLimiter.check(rl, "k", 2, 5_000)

    # At time 1000 a sweep must prune with the last-seen 5000ms window, keeping both
    # entries. Using the stale 500ms window would drop the key entirely.
    Clock.advance(900)
    send(rl, :cleanup)

    # Both time-0 and time-100 entries are still active under 5000ms, so a limit of
    # 2 is now exhausted; retry_after is oldest(0) + 5000 - 1000 = 4000.
    assert {:error, :rate_limited, 4_000} = RateLimiter.check(rl, "k", 2, 5_000)
  end

  test "check/4 raises on non-integer limits", %{rl: rl} do
    assert_raise FunctionClauseError, fn ->
      RateLimiter.check(rl, "k", 2.0, 1_000)
    end

    assert_raise FunctionClauseError, fn ->
      RateLimiter.check(rl, "k", 2, 1_000.0)
    end

    assert Process.alive?(rl)
  end

  test "start_link with no arguments starts an empty server" do
    {:ok, pid} = RateLimiter.start_link()
    assert is_pid(pid)

    # Freshly started with zero keys tracked: the first check for any key is
    # allowed with remaining = max - 1, independent of the (real) clock value.
    assert {:ok, 4} = RateLimiter.check(pid, "fresh", 5, 1_000)
  end

  # -------------------------------------------------------
  # The periodic sweep is driven by an automatically scheduled timer
  # -------------------------------------------------------

  test "the periodic cleanup timer fires and re-arms automatically" do
    test_pid = self()

    # The clock is called afresh on every cleanup pass. This probe records each
    # such call; no check/4 is issued, so every tick is an automatic sweep.
    clock = fn ->
      send(test_pid, :cleanup_clock_tick)
      0
    end

    # A real, short documented interval drives the timer.
    {:ok, _pid} = RateLimiter.start_link(clock: clock, cleanup_interval_ms: 25)

    # The first tick proves the startup timer fired; the second proves the pass
    # re-armed the next one, so the sweep repeats rather than running just once.
    # A scheduler that never arms Process.send_after would produce no ticks.
    assert_receive :cleanup_clock_tick, 1_000
    assert_receive :cleanup_clock_tick, 1_000
  end
end
```
