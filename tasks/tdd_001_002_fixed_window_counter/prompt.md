# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

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
    assert {:ok, 1} = FixedWindowLimiter.check(fw, "x", 2, 1_000)
    assert {:ok, 4} = FixedWindowLimiter.check(fw, "y", 5, 2_000)
    assert {:ok, 0} = FixedWindowLimiter.check(fw, "x", 2, 1_000)
    assert {:ok, 3} = FixedWindowLimiter.check(fw, "y", 5, 2_000)

    assert {:error, :rate_limited, _} = FixedWindowLimiter.check(fw, "x", 2, 1_000)
    assert {:ok, 2} = FixedWindowLimiter.check(fw, "y", 5, 2_000)
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

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
