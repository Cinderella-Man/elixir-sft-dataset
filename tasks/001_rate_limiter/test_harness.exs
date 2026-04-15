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

    # Trigger cleanup manually via a message
    # The GenServer should handle a :cleanup message
    send(rl, :cleanup)
    # Give it a moment to process
    :sys.get_state(rl)

    # Now the internal state should not hold 100 keys worth of data
    state = :sys.get_state(rl)
    assert map_size(state.keys) == 0

    # The state is implementation-dependent, but we can check it's a
    # map/struct and that expired keys are gone. We verify by checking
    # that new requests for those keys work fresh (remaining = max - 1)
    assert {:ok, 0} = RateLimiter.check(rl, "key:1", 1, 100)
  end
end
