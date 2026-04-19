defmodule SwrCacheTest do
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

  defmodule Loader do
    use Agent

    def start_link(values) do
      Agent.start_link(fn -> %{values: values, calls: 0} end, name: __MODULE__)
    end

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

    def slow_next_value(sleep_ms) do
      Process.sleep(sleep_ms)
      next_value()
    end

    def calls, do: Agent.get(__MODULE__, & &1.calls)
  end

  setup do
    start_supervised!({Clock, 0})

    {:ok, pid} =
      SwrCache.start_link(
        clock: &Clock.now/0,
        sweep_interval_ms: :infinity
      )

    %{c: pid}
  end

  defp wait_for_idle(c, timeout_ms \\ 500) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms

    Stream.repeatedly(fn ->
      case SwrCache.stats(c) do
        %{revalidations_in_flight: 0} -> :idle
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
  # Three-way return shape
  # -------------------------------------------------------

  test "fresh window returns {:ok, value, :fresh}", %{c: c} do
    :ok = SwrCache.put(c, :a, :v1, 1_000, 2_000, fn -> :should_not_be_called end)

    assert {:ok, :v1, :fresh} = SwrCache.get(c, :a)

    Clock.advance(999)
    assert {:ok, :v1, :fresh} = SwrCache.get(c, :a)
  end

  test "stale window returns {:ok, value, :stale}", %{c: c} do
    start_supervised!({Loader, [:v2]})

    :ok = SwrCache.put(c, :a, :v1, 1_000, 2_000, &Loader.next_value/0)

    Clock.advance(1_000)
    assert {:ok, :v1, :stale} = SwrCache.get(c, :a)
  end

  test "past hard expiry returns :miss and evicts", %{c: c} do
    :ok = SwrCache.put(c, :a, :v1, 1_000, 2_000, fn -> :never end)

    Clock.advance(3_000)
    assert :miss = SwrCache.get(c, :a)
    assert %{entries: 0} = SwrCache.stats(c)
  end

  test "missing key returns :miss", %{c: c} do
    assert :miss = SwrCache.get(c, :nope)
  end

  # -------------------------------------------------------
  # Revalidation trigger — the defining behavior
  # -------------------------------------------------------

  test "stale read triggers revalidation; later reads see new value", %{c: c} do
    start_supervised!({Loader, [:v2]})

    :ok = SwrCache.put(c, :a, :v1, 1_000, 2_000, &Loader.next_value/0)

    # Enter stale window
    Clock.advance(1_000)
    assert {:ok, :v1, :stale} = SwrCache.get(c, :a)

    :ok = wait_for_idle(c)
    assert Loader.calls() == 1

    # New value is :v2, and since revalidation happened at t=1000, it's fresh
    # until t=2000.
    assert {:ok, :v2, :fresh} = SwrCache.get(c, :a)
  end

  test "fresh reads do NOT trigger revalidation", %{c: c} do
    start_supervised!({Loader, [:never_called]})

    :ok = SwrCache.put(c, :a, :v1, 1_000, 2_000, &Loader.next_value/0)

    # Read 5 times well within the fresh window
    for _ <- 1..5, do: assert({:ok, :v1, :fresh} = SwrCache.get(c, :a))

    :ok = wait_for_idle(c)
    assert Loader.calls() == 0
  end

  test "concurrent stale reads trigger only ONE revalidation", %{c: c} do
    start_supervised!({Loader, [:v2]})

    :ok =
      SwrCache.put(c, :a, :v1, 1_000, 2_000, fn -> Loader.slow_next_value(100) end)

    Clock.advance(1_000)

    # Fire many stale reads while a slow revalidation is still in flight.
    for _ <- 1..10, do: assert({:ok, :v1, :stale} = SwrCache.get(c, :a))

    assert %{revalidations_in_flight: 1} = SwrCache.stats(c)

    :ok = wait_for_idle(c)
    assert Loader.calls() == 1
  end

  # -------------------------------------------------------
  # Revalidation resets BOTH fresh and stale windows
  # -------------------------------------------------------

  test "successful revalidation gives new full fresh+stale budget", %{c: c} do
    start_supervised!({Loader, [:v2]})

    :ok = SwrCache.put(c, :a, :v1, 1_000, 2_000, &Loader.next_value/0)

    Clock.advance(1_500)
    SwrCache.get(c, :a)
    :ok = wait_for_idle(c)

    # Revalidation happened at t=1500 so fresh until t=2500, stale until t=4500
    # t=2499
    Clock.advance(999)
    assert {:ok, :v2, :fresh} = SwrCache.get(c, :a)

    # t=2501
    Clock.advance(2)
    assert {:ok, :v2, :stale} = SwrCache.get(c, :a)
  end

  # -------------------------------------------------------
  # Failed revalidation leaves entry stale (reread triggers retry)
  # -------------------------------------------------------

  test "failed revalidation leaves entry in place; next stale read retries", %{c: c} do
    # Loader that raises — but after a retry, returns a value
    start_supervised!({Loader, [:from_retry]})

    counter = :counters.new(1, [])
    :counters.put(counter, 1, 0)

    loader = fn ->
      :counters.add(counter, 1, 1)

      if :counters.get(counter, 1) == 1 do
        raise "first call always fails"
      else
        Loader.next_value()
      end
    end

    :ok = SwrCache.put(c, :a, :v1, 1_000, 2_000, loader)

    Clock.advance(1_000)
    assert {:ok, :v1, :stale} = SwrCache.get(c, :a)
    :ok = wait_for_idle(c)

    # Failed revalidation → entry unchanged (still the original :v1, still stale)
    assert {:ok, :v1, :stale} = SwrCache.get(c, :a)
    :ok = wait_for_idle(c)

    assert {:ok, :from_retry, :fresh} = SwrCache.get(c, :a)
  end

  # -------------------------------------------------------
  # Delete invalidates in-flight revalidation
  # -------------------------------------------------------

  test "delete during in-flight revalidation discards the result", %{c: c} do
    start_supervised!({Loader, [:v2]})

    :ok =
      SwrCache.put(c, :a, :v1, 1_000, 2_000, fn -> Loader.slow_next_value(100) end)

    Clock.advance(1_000)
    # triggers slow revalidation
    SwrCache.get(c, :a)

    SwrCache.delete(c, :a)

    :ok = wait_for_idle(c)
    assert :miss = SwrCache.get(c, :a)
    assert %{entries: 0} = SwrCache.stats(c)
  end

  # -------------------------------------------------------
  # Put during in-flight revalidation wins
  # -------------------------------------------------------

  test "put during revalidation: revalidation result must not clobber", %{c: c} do
    start_supervised!({Loader, [:from_loader]})

    :ok =
      SwrCache.put(c, :a, :v1, 1_000, 2_000, fn -> Loader.slow_next_value(100) end)

    Clock.advance(1_000)
    # trigger slow revalidation
    SwrCache.get(c, :a)

    # User puts a new value before the revalidation completes
    SwrCache.put(c, :a, :user_set, 500, 1_000, fn -> :ignored end)

    :ok = wait_for_idle(c)

    # The user's put must win — value AND the fresh window is from the put's time
    assert {:ok, :user_set, :fresh} = SwrCache.get(c, :a)
  end

  # -------------------------------------------------------
  # Sweep removes past-stale entries only
  # -------------------------------------------------------

  test "sweep removes entries past stale window, keeps stale-but-live entries", %{c: c} do
    # Reset Clock to 0 (setup already started it)
    Clock.set(0)

    # hard expires at 300
    :ok = SwrCache.put(c, :a, 1, 100, 200, fn -> :_ end)
    # hard expires at 3000
    :ok = SwrCache.put(c, :b, 2, 200, 2_800, fn -> :_ end)

    Clock.advance(500)
    send(c, :sweep)
    :sys.get_state(c)

    assert :miss = SwrCache.get(c, :a)
    # :b is stale now (t=500, fresh_until=200) but NOT past hard expiry (3000)
    assert {:ok, 2, :stale} = SwrCache.get(c, :b)
  end

  # -------------------------------------------------------
  # Validation
  # -------------------------------------------------------

  test "put rejects non-positive windows", %{c: c} do
    assert_raise FunctionClauseError, fn ->
      SwrCache.put(c, :a, 1, 0, 100, fn -> :_ end)
    end

    assert_raise FunctionClauseError, fn ->
      SwrCache.put(c, :a, 1, 100, 0, fn -> :_ end)
    end
  end
end
