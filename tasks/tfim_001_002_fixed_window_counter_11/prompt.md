# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule FixedWindowLimiter do
  @moduledoc """
  A GenServer that enforces per-key rate limits using a fixed-window counter.

  Time is snapped into discrete windows of size `window_ms`: a timestamp `t`
  belongs to window `div(t, window_ms)`.  Each `{key, window_index}` pair has
  its own counter.  A request is allowed if the counter for the current
  window is below `max_requests`, in which case the counter is incremented.

  Because windows are absolute, counters reset abruptly at window boundaries.
  This allows up to `2 * max_requests` requests across a boundary (e.g.,
  `max_requests` at the very end of window N and another `max_requests` at
  the very start of window N+1).  That is a known property of the fixed-
  window counter algorithm and is accepted here as a tradeoff for
  implementation simplicity and O(1) state per key.

  Expired counters are pruned during a periodic sweep so the process doesn't
  leak memory for keys that stop receiving traffic.

  ## Options

    * `:name`                 – process registration name (optional)
    * `:clock`                – zero-arity function returning current time in ms
                                (default: `fn -> System.monotonic_time(:millisecond) end`)
    * `:cleanup_interval_ms`  – how often the periodic sweep runs in ms (default: 60_000)

  ## Examples

      iex> {:ok, pid} = FixedWindowLimiter.start_link([])
      iex> {:ok, 4} = FixedWindowLimiter.check(pid, "user:1", 5, 1_000)
      iex> {:ok, 3} = FixedWindowLimiter.check(pid, "user:1", 5, 1_000)

  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the FixedWindowLimiter process and links it to the caller.

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
  Checks whether a request for `key` is allowed in the current fixed window.

  Returns `{:ok, remaining}` when the request is accepted, where `remaining`
  is the number of additional requests permitted in the same window.

  Returns `{:error, :rate_limited, retry_after_ms}` when the window's counter
  has reached `max_requests`.  `retry_after_ms` is the wait (in milliseconds)
  until the current window ends and a fresh counter begins.
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
       # %{{key, window_index} => {count, window_end_time}}
       counters: %{},
       clock: clock,
       cleanup_interval_ms: cleanup_interval
     }}
  end

  @impl true
  def handle_call({:check, key, max_requests, window_ms}, _from, state) do
    now = state.clock.()

    # Snap `now` into the absolute window it belongs to.
    window_index = div(now, window_ms)
    window_end = (window_index + 1) * window_ms
    counter_key = {key, window_index}

    count = Map.get(state.counters, counter_key, {0, window_end}) |> elem(0)

    if count < max_requests do
      new_count = count + 1
      remaining = max_requests - new_count
      new_counters = Map.put(state.counters, counter_key, {new_count, window_end})

      {:reply, {:ok, remaining}, %{state | counters: new_counters}}
    else
      # Counter saturated; wait until this window ends.
      retry_after = max(window_end - now, 1)
      {:reply, {:error, :rate_limited, retry_after}, state}
    end
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = state.clock.()

    cleaned =
      state.counters
      |> Enum.reduce(%{}, fn {ck, {count, window_end} = entry}, acc ->
        # Keep only counters whose window has not yet ended.
        if window_end > now do
          Map.put(acc, ck, entry)
        else
          _ = count
          acc
        end
      end)

    schedule_cleanup(state.cleanup_interval_ms)

    {:noreply, %{state | counters: cleaned}}
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
defmodule FixedWindowLimiterTest do
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
      FixedWindowLimiter.start_link(
        clock: &Clock.now/0,
        # disable auto-cleanup in tests
        cleanup_interval_ms: :infinity
      )

    %{fw: pid}
  end

  # -------------------------------------------------------
  # Basic allow / reject
  # -------------------------------------------------------

  test "allows requests up to the limit within a window", %{fw: fw} do
    assert {:ok, 2} = FixedWindowLimiter.check(fw, "user:1", 3, 1_000)
    assert {:ok, 1} = FixedWindowLimiter.check(fw, "user:1", 3, 1_000)
    assert {:ok, 0} = FixedWindowLimiter.check(fw, "user:1", 3, 1_000)
  end

  test "rejects requests past the limit within a window", %{fw: fw} do
    for _ <- 1..3, do: FixedWindowLimiter.check(fw, "k", 3, 1_000)

    assert {:error, :rate_limited, retry_after} =
             FixedWindowLimiter.check(fw, "k", 3, 1_000)

    assert is_integer(retry_after)
    assert retry_after > 0
    assert retry_after <= 1_000
  end

  # -------------------------------------------------------
  # Window reset behaviour (the defining property)
  # -------------------------------------------------------

  test "counter resets abruptly at window boundary", %{fw: fw} do
    # Fill up window 0 (t=0..999)
    for _ <- 1..3, do: FixedWindowLimiter.check(fw, "k", 3, 1_000)
    assert {:error, :rate_limited, _} = FixedWindowLimiter.check(fw, "k", 3, 1_000)

    # Cross into window 1 (t=1000..1999). Counter resets.
    Clock.set(1_000)
    assert {:ok, 2} = FixedWindowLimiter.check(fw, "k", 3, 1_000)
    assert {:ok, 1} = FixedWindowLimiter.check(fw, "k", 3, 1_000)
    assert {:ok, 0} = FixedWindowLimiter.check(fw, "k", 3, 1_000)
    assert {:error, :rate_limited, _} = FixedWindowLimiter.check(fw, "k", 3, 1_000)
  end

  test "boundary burst is allowed (known property of fixed windows)", %{fw: fw} do
    # Fill window 0 at t=999 — the very end of the window
    Clock.set(999)
    for _ <- 1..3, do: FixedWindowLimiter.check(fw, "k", 3, 1_000)
    assert {:error, :rate_limited, _} = FixedWindowLimiter.check(fw, "k", 3, 1_000)

    # Jump 1ms forward into window 1 — fresh counter, full allowance
    Clock.set(1_000)
    assert {:ok, 2} = FixedWindowLimiter.check(fw, "k", 3, 1_000)
    assert {:ok, 1} = FixedWindowLimiter.check(fw, "k", 3, 1_000)
    assert {:ok, 0} = FixedWindowLimiter.check(fw, "k", 3, 1_000)

    # 6 requests within 1ms of wall-clock time — the well-known
    # fixed-window-boundary burst. This is accepted by this implementation.
    assert {:error, :rate_limited, _} = FixedWindowLimiter.check(fw, "k", 3, 1_000)
  end

  test "requests mid-window don't reset the counter", %{fw: fw} do
    # t=0: first request
    assert {:ok, 2} = FixedWindowLimiter.check(fw, "k", 3, 1_000)

    # t=400: second request (still in window 0)
    Clock.advance(400)
    assert {:ok, 1} = FixedWindowLimiter.check(fw, "k", 3, 1_000)

    # t=800: third request (still in window 0)
    Clock.advance(400)
    assert {:ok, 0} = FixedWindowLimiter.check(fw, "k", 3, 1_000)

    # t=800: fourth request — rejected, counter at 3
    assert {:error, :rate_limited, _} = FixedWindowLimiter.check(fw, "k", 3, 1_000)

    # t=999: still in window 0, still rejected
    Clock.set(999)
    assert {:error, :rate_limited, _} = FixedWindowLimiter.check(fw, "k", 3, 1_000)
  end

  # -------------------------------------------------------
  # Key independence
  # -------------------------------------------------------

  test "different keys are completely independent", %{fw: fw} do
    # Exhaust key "a"
    for _ <- 1..3, do: FixedWindowLimiter.check(fw, "a", 3, 1_000)
    assert {:error, :rate_limited, _} = FixedWindowLimiter.check(fw, "a", 3, 1_000)

    # Key "b" should be unaffected
    assert {:ok, 2} = FixedWindowLimiter.check(fw, "b", 3, 1_000)
    assert {:ok, 1} = FixedWindowLimiter.check(fw, "b", 3, 1_000)
    assert {:ok, 0} = FixedWindowLimiter.check(fw, "b", 3, 1_000)
  end

  # -------------------------------------------------------
  # retry_after accuracy
  # -------------------------------------------------------

  test "retry_after reports time until window ends", %{fw: fw} do
    # Fill window 0 at t=0
    for _ <- 1..3, do: FixedWindowLimiter.check(fw, "k", 3, 1_000)

    # Advance to t=300
    Clock.advance(300)

    assert {:error, :rate_limited, retry_after} =
             FixedWindowLimiter.check(fw, "k", 3, 1_000)

    # Window 0 ends at t=1000. We're at t=300, so retry_after should be 700.
    assert retry_after == 700
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "max_requests of 1 allows exactly one call per window", %{fw: fw} do
    assert {:ok, 0} = FixedWindowLimiter.check(fw, "k", 1, 500)
    assert {:error, :rate_limited, _} = FixedWindowLimiter.check(fw, "k", 1, 500)

    # Next window starts at t=500
    Clock.set(500)
    assert {:ok, 0} = FixedWindowLimiter.check(fw, "k", 1, 500)
  end

  test "works with very large window", %{fw: fw} do
    assert {:ok, 0} = FixedWindowLimiter.check(fw, "k", 1, 86_400_000)
    assert {:error, :rate_limited, _} = FixedWindowLimiter.check(fw, "k", 1, 86_400_000)

    # Next day's window
    Clock.set(86_400_000)
    assert {:ok, 0} = FixedWindowLimiter.check(fw, "k", 1, 86_400_000)
  end

  # -------------------------------------------------------
  # Multiple keys interleaved
  # -------------------------------------------------------

  test "interleaved operations on multiple keys", %{fw: fw} do
    # TODO
  end

  # -------------------------------------------------------
  # Cleanup (memory leak prevention)
  # -------------------------------------------------------

  test "expired window counters are cleaned up and don't accumulate", %{fw: fw} do
    # Create counter entries for 100 different keys in window 0 (t=0, window_ms=100)
    for i <- 1..100 do
      FixedWindowLimiter.check(fw, "key:#{i}", 1, 100)
    end

    # Advance past the window end (window 0 ends at t=100)
    Clock.advance(200)

    # Trigger the sweep manually via the documented :cleanup message
    send(fw, :cleanup)

    # A GenServer processes its mailbox in order, so the calls below also
    # confirm the sweep finished without crashing the server. Internal state
    # is implementation-dependent and deliberately not inspected; the
    # observable contract is that previously tracked keys start a fresh
    # window after expiry (remaining = max - 1).
    assert {:ok, 0} = FixedWindowLimiter.check(fw, "key:1", 1, 100)
    assert {:ok, 0} = FixedWindowLimiter.check(fw, "key:100", 1, 100)
    assert Process.alive?(fw)
  end

  test "cleanup discards the counter of a window that has fully ended", %{fw: fw} do
    # Exhaust window 0 (t=0..99) for this key.
    assert {:ok, 0} = FixedWindowLimiter.check(fw, "gone", 1, 100)
    assert {:error, :rate_limited, _} = FixedWindowLimiter.check(fw, "gone", 1, 100)

    # At t=200 window 0 has fully ended (its end, t=100, is before now), so the
    # sweep must drop that counter entry.
    Clock.set(200)
    send(fw, :cleanup)

    # Mailbox order: this reply proves the sweep above already ran, so the
    # clock cannot be moved before the sweep observes t=200.
    assert {:ok, 0} = FixedWindowLimiter.check(fw, "flush", 1, 100)

    # Observing a time that maps back onto window 0: the entry is gone, so the
    # counter starts from zero. Had the sweep left it in place, the stale
    # saturated counter would still reject this request.
    Clock.set(0)
    assert {:ok, 0} = FixedWindowLimiter.check(fw, "gone", 1, 100)
  end

  test "cleanup preserves counters whose window has not yet ended", %{fw: fw} do
    # One of two allowed requests in window 0 (t=0..999).
    assert {:ok, 1} = FixedWindowLimiter.check(fw, "live", 2, 1_000)

    # t=50 is still inside window 0, which ends at t=1000, so the sweep removes
    # nothing: only counters whose window has fully ended are dropped.
    Clock.set(50)
    send(fw, :cleanup)

    # The surviving counter still stands at 1, leaving exactly one request.
    assert {:ok, 0} = FixedWindowLimiter.check(fw, "live", 2, 1_000)
    assert {:error, :rate_limited, _} = FixedWindowLimiter.check(fw, "live", 2, 1_000)
  end

  test "periodic sweep runs automatically on the configured interval" do
    interval_ms = 25

    {:ok, auto} =
      FixedWindowLimiter.start_link(
        clock: &Clock.now/0,
        cleanup_interval_ms: interval_ms
      )

    # Arm the probe: window 0 (t=0..99) is exhausted for this key.
    Clock.set(0)
    assert {:ok, 0} = FixedWindowLimiter.check(auto, "probe", 1, 100)

    # From t=200 onwards window 0 has fully ended, so a sweep that nobody
    # triggers by hand must eventually discard the probe's counter.
    Clock.set(200)

    # Generous bound: 80 intervals of observation before giving up.
    deadline = System.monotonic_time(:millisecond) + interval_ms * 80
    assert :pruned = await_probe_pruned(auto, deadline)
  end

  # Polls the probe key until an automatic sweep has removed its expired
  # counter, or the deadline passes. Each probe reads a time inside the
  # already-ended window 0: a rejection means the stale counter is still
  # tracked, `{:ok, 0}` means it was swept away (and re-arms the probe).
  defp await_probe_pruned(server, deadline) do
    Clock.set(0)
    result = FixedWindowLimiter.check(server, "probe", 1, 100)
    Clock.set(200)

    cond do
      match?({:ok, 0}, result) ->
        :pruned

      System.monotonic_time(:millisecond) >= deadline ->
        :timed_out

      true ->
        Process.sleep(5)
        await_probe_pruned(server, deadline)
    end
  end

  test "registers under :name and serves calls via the registered name" do
    name = :fixed_window_limiter_named_test

    {:ok, pid} =
      FixedWindowLimiter.start_link(
        name: name,
        clock: &Clock.now/0,
        cleanup_interval_ms: :infinity
      )

    assert Process.whereis(name) == pid
    assert {:ok, 0} = FixedWindowLimiter.check(name, "k", 1, 1_000)
    assert {:error, :rate_limited, _} = FixedWindowLimiter.check(name, "k", 1, 1_000)
  end
end
```
