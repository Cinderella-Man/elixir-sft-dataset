defmodule RefreshAheadCacheTest do
  use ExUnit.Case, async: false

  defmodule Clock do
    use Agent

    def start_link(initial \\ 0) do
      Agent.start_link(fn -> initial end, name: __MODULE__)
    end

    def now, do: Agent.get(__MODULE__, & &1)
    def advance(ms), do: Agent.update(__MODULE__, &(&1 + ms))
    def set(ms), do: Agent.update(__MODULE__, fn _ -> ms end)
  end

  # A programmable loader backed by an Agent — lets tests control what the
  # loader returns and count its invocations.
  defmodule Loader do
    def start_link(values) do
      Agent.start_link(fn -> %{values: values, calls: 0} end, name: __MODULE__)
    end

    # Returns the next queued value, incrementing the call count.
    def next_value do
      Agent.get_and_update(__MODULE__, fn s ->
        {v, rest} =
          case s.values do
            [v | rest] -> {v, rest}
            [] -> {:no_more_values, []}
          end

        {v, %{s | values: rest, calls: s.calls + 1}}
      end)
    end

    # A slow loader: sleeps, then calls `next_value/0`.  Used to create
    # observable "refresh in flight" windows.
    def slow_next_value(sleep_ms) do
      Process.sleep(sleep_ms)
      next_value()
    end

    def calls, do: Agent.get(__MODULE__, & &1.calls)
  end

  setup do
    start_supervised!({Clock, 0})

    {:ok, pid} =
      RefreshAheadCache.start_link(
        clock: &Clock.now/0,
        sweep_interval_ms: :infinity,
        refresh_threshold: 0.8
      )

    %{c: pid}
  end

  # Wait for any in-flight refreshes to settle.  We poll stats instead of
  # sleeping a fixed duration to keep tests robust.
  defp wait_for_idle(c, timeout_ms \\ 500) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms

    Stream.repeatedly(fn ->
      case RefreshAheadCache.stats(c) do
        %{refreshes_in_flight: 0} -> :idle
        _ -> :busy
      end
    end)
    |> Enum.reduce_while(nil, fn
      :idle, _ ->
        {:halt, :ok}

      :busy, _ ->
        if System.monotonic_time(:millisecond) > deadline do
          {:halt, :timeout}
        else
          Process.sleep(5)
          {:cont, nil}
        end
    end)
  end

  # -------------------------------------------------------
  # Basic put/get/delete (TTLCache parity)
  # -------------------------------------------------------

  test "put/get round-trip", %{c: c} do
    :ok = RefreshAheadCache.put(c, :a, 1, 1_000, fn -> :should_not_be_called end)
    assert {:ok, 1} = RefreshAheadCache.get(c, :a)
  end

  test "missing key returns :miss", %{c: c} do
    assert :miss = RefreshAheadCache.get(c, :nope)
  end

  test "hard expiry returns :miss and evicts", %{c: c} do
    :ok = RefreshAheadCache.put(c, :a, 1, 1_000, fn -> :never end)

    Clock.advance(1_000)
    assert :miss = RefreshAheadCache.get(c, :a)

    assert %{entries: 0} = RefreshAheadCache.stats(c)
  end

  test "delete removes entry", %{c: c} do
    :ok = RefreshAheadCache.put(c, :a, 1, 1_000, fn -> :never end)
    :ok = RefreshAheadCache.delete(c, :a)
    assert :miss = RefreshAheadCache.get(c, :a)
  end

  # -------------------------------------------------------
  # No refresh below threshold
  # -------------------------------------------------------

  test "get below refresh threshold does NOT trigger loader", %{c: c} do
    start_supervised!({Loader, [:v2]})

    :ok = RefreshAheadCache.put(c, :a, :v1, 1_000, &Loader.next_value/0)

    # threshold 0.8 of 1000ms = 800ms.  At 500ms we are still "fresh."
    Clock.advance(500)
    assert {:ok, :v1} = RefreshAheadCache.get(c, :a)

    :ok = wait_for_idle(c)
    assert Loader.calls() == 0
  end

  # -------------------------------------------------------
  # Refresh triggered at threshold (the defining property)
  # -------------------------------------------------------

  test "get past refresh threshold triggers loader; subsequent gets see new value", %{c: c} do
    start_supervised!({Loader, [:v2]})

    :ok = RefreshAheadCache.put(c, :a, :v1, 1_000, &Loader.next_value/0)

    # Past threshold (0.8 * 1000 = 800ms).
    Clock.advance(850)

    # This get returns the OLD value and schedules a refresh.
    assert {:ok, :v1} = RefreshAheadCache.get(c, :a)

    :ok = wait_for_idle(c)
    assert Loader.calls() == 1

    # Next get should see the refreshed value.
    assert {:ok, :v2} = RefreshAheadCache.get(c, :a)
  end

  test "refresh resets TTL to now + original ttl_ms", %{c: c} do
    start_supervised!({Loader, [:v2]})

    :ok = RefreshAheadCache.put(c, :a, :v1, 1_000, &Loader.next_value/0)

    Clock.advance(850)
    RefreshAheadCache.get(c, :a)
    :ok = wait_for_idle(c)

    # The refresh applied at t=850 should set expires_at = 850 + 1000 = 1850.
    # So at t=1700 we're still fresh.
    Clock.advance(850)
    assert {:ok, :v2} = RefreshAheadCache.get(c, :a)

    # At t=1900 we're past the NEW expiry.
    Clock.advance(200)
    assert :miss = RefreshAheadCache.get(c, :a)
  end

  # -------------------------------------------------------
  # Only one refresh in flight per key
  # -------------------------------------------------------

  test "rapid gets past threshold only trigger ONE refresh", %{c: c} do
    start_supervised!({Loader, [:v2]})

    # Use a slow loader to ensure the first refresh is still in flight while
    # we fire the follow-up gets.
    :ok =
      RefreshAheadCache.put(c, :a, :v1, 1_000, fn -> Loader.slow_next_value(100) end)

    Clock.advance(850)

    # 10 rapid reads
    for _ <- 1..10, do: assert({:ok, :v1} = RefreshAheadCache.get(c, :a))

    # Should see exactly 1 refresh in flight
    %{refreshes_in_flight: n} = RefreshAheadCache.stats(c)
    assert n == 1

    :ok = wait_for_idle(c)
    assert Loader.calls() == 1
  end

  # -------------------------------------------------------
  # Delete cancels the effect of an in-flight refresh
  # -------------------------------------------------------

  test "delete during in-flight refresh discards the refresh result", %{c: c} do
    start_supervised!({Loader, [:v2]})

    :ok =
      RefreshAheadCache.put(c, :a, :v1, 1_000, fn -> Loader.slow_next_value(100) end)

    Clock.advance(850)

    # Trigger refresh
    RefreshAheadCache.get(c, :a)
    %{refreshes_in_flight: 1} = RefreshAheadCache.stats(c)

    # Delete while refresh is in flight
    RefreshAheadCache.delete(c, :a)

    # Wait for the refresh to complete — it should have been discarded
    :ok = wait_for_idle(c)
    assert :miss = RefreshAheadCache.get(c, :a)
    assert %{entries: 0} = RefreshAheadCache.stats(c)
  end

  # -------------------------------------------------------
  # Put during in-flight refresh invalidates the refresh
  # -------------------------------------------------------

  test "put during in-flight refresh: the refresh result must not clobber", %{c: c} do
    start_supervised!({Loader, [:from_loader]})

    :ok =
      RefreshAheadCache.put(c, :a, :v1, 1_000, fn -> Loader.slow_next_value(100) end)

    Clock.advance(850)
    RefreshAheadCache.get(c, :a)   # triggers slow refresh

    # User overwrites manually before refresh completes
    RefreshAheadCache.put(c, :a, :user_set, 1_000, fn -> :ignored end)

    :ok = wait_for_idle(c)

    # The manual put must win
    assert {:ok, :user_set} = RefreshAheadCache.get(c, :a)
  end

  # -------------------------------------------------------
  # Refresh failures leave the existing value intact
  # -------------------------------------------------------

  test "a failing loader leaves the current value in place", %{c: c} do
    :ok =
      RefreshAheadCache.put(c, :a, :good, 1_000, fn -> raise "nope" end)

    Clock.advance(850)
    assert {:ok, :good} = RefreshAheadCache.get(c, :a)

    :ok = wait_for_idle(c)
    assert %{refreshes_in_flight: 0} = RefreshAheadCache.stats(c)

    # Still returns the original value
    assert {:ok, :good} = RefreshAheadCache.get(c, :a)
  end

  # -------------------------------------------------------
  # Hard expiry sweep
  # -------------------------------------------------------

  test "sweep removes hard-expired entries" do
    start_supervised!({Clock, 0})

    {:ok, c} =
      RefreshAheadCache.start_link(
        clock: &Clock.now/0,
        sweep_interval_ms: :infinity,
        refresh_threshold: 0.8
      )

    :ok = RefreshAheadCache.put(c, :a, 1, 1_000, fn -> 99 end)
    :ok = RefreshAheadCache.put(c, :b, 2, 5_000, fn -> 99 end)

    Clock.advance(2_000)
    send(c, :sweep)
    :sys.get_state(c)

    assert :miss = RefreshAheadCache.get(c, :a)
    assert {:ok, 2} = RefreshAheadCache.get(c, :b)
  end

  # -------------------------------------------------------
  # Option validation
  # -------------------------------------------------------

  test "invalid refresh_threshold raises" do
    assert_raise ArgumentError, fn ->
      RefreshAheadCache.start_link(refresh_threshold: 0.0)
    end

    assert_raise ArgumentError, fn ->
      RefreshAheadCache.start_link(refresh_threshold: 1.5)
    end
  end
end
