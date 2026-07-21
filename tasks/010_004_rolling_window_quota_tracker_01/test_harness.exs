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
    assert {:ok, 0} = QuotaTracker.record(t, :api, 10, 10, 1_000)
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
