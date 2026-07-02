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
    :sys.get_state(t)

    state = :sys.get_state(t)
    assert map_size(state.entries) == 0
  end

  test "cleanup only removes fully expired keys, keeps active ones", %{tracker: t} do
    {:ok, _} = QuotaTracker.record(t, :old, 5, 10, 1_000)

    Clock.advance(9_000)
    {:ok, _} = QuotaTracker.record(t, :new, 3, 10, 1_000)

    Clock.advance(1_001)

    send(t, :cleanup)
    :sys.get_state(t)

    state = :sys.get_state(t)
    assert not Map.has_key?(state.entries, :old)
    assert Map.has_key?(state.entries, :new)
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
end
