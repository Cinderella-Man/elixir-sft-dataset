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
    # Entry recorded at time 0 with a 1000ms window.
    assert {:ok, 0} = RateLimiter.check(rl, "k", 1, 1_000)

    # At exactly time 1000 the entry is not active (0 > 1000 - 1000 is false),
    # so the key's active list is empty and the key is removed entirely.
    Clock.advance(1_000)
    send(rl, :cleanup)

    # A removed key behaves exactly like a never-seen key: checked here with a
    # wider window that would still have covered the time-0 entry had it been
    # retained, the first call must be allowed with remaining = max - 1.
    assert {:ok, 0} = RateLimiter.check(rl, "k", 1, 2_000)
    assert Process.alive?(rl)
  end
end
