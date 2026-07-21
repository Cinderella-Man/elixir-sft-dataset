# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
defmodule CounterTSDBTest do
  use ExUnit.Case, async: false

  defmodule Clock do
    use Agent

    def start_link(initial \\ 0) do
      Agent.start_link(fn -> initial end, name: __MODULE__)
    end

    def now, do: Agent.get(__MODULE__, & &1)
    def set(ms), do: Agent.update(__MODULE__, fn _ -> ms end)
  end

  setup do
    start_supervised!({Clock, 0})

    {:ok, pid} =
      CounterTSDB.start_link(
        clock: &Clock.now/0,
        chunk_duration_ms: 1_000,
        retention_ms: 10_000,
        cleanup_interval_ms: :infinity
      )

    %{db: pid}
  end

  # -------------------------------------------------------
  # Raw query
  # -------------------------------------------------------

  test "insert and query returns sorted points within inclusive range", %{db: db} do
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "a"}, 300, 30)
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "a"}, 100, 10)
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "a"}, 200, 20)

    [{%{"i" => "a"}, points}] = CounterTSDB.query(db, "reqs", %{"i" => "a"}, {0, 500})
    assert points == [{100, 10}, {200, 20}, {300, 30}]
  end

  test "query omits series with no points in range", %{db: db} do
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "a"}, 100, 10)
    assert [] = CounterTSDB.query(db, "reqs", %{"i" => "a"}, {500, 600})
  end

  # -------------------------------------------------------
  # :increase (reset-aware)
  # -------------------------------------------------------

  test "increase over a monotonic window is the difference", %{db: db} do
    :ok = CounterTSDB.insert(db, "reqs", %{}, 0, 100)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 500, 160)

    [{_labels, range}] = CounterTSDB.query_range(db, "reqs", %{}, {0, 1000}, :increase, 1_000)
    assert range == [{0, 60}]
  end

  test "increase treats a mid-window drop as a counter reset", %{db: db} do
    # values 10, 15, 5, 8 -> deltas 5, (reset)5, 3 -> total 13
    :ok = CounterTSDB.insert(db, "reqs", %{}, 0, 10)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 100, 15)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 200, 5)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 300, 8)

    [{_labels, range}] = CounterTSDB.query_range(db, "reqs", %{}, {0, 1000}, :increase, 1_000)
    assert range == [{0, 13}]
  end

  test "increase omits windows with fewer than 2 points", %{db: db} do
    # window [0,1000): only 1 point -> omitted
    :ok = CounterTSDB.insert(db, "reqs", %{}, 100, 42)
    # window [1000,2000): 2 points -> increase 50
    :ok = CounterTSDB.insert(db, "reqs", %{}, 1100, 10)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 1600, 60)

    [{_labels, range}] = CounterTSDB.query_range(db, "reqs", %{}, {0, 2000}, :increase, 1_000)
    assert range == [{1000, 50}]
  end

  test "increase buckets points into separate windows", %{db: db} do
    :ok = CounterTSDB.insert(db, "reqs", %{}, 0, 10)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 100, 20)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 1000, 100)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 1500, 130)

    [{_labels, range}] = CounterTSDB.query_range(db, "reqs", %{}, {0, 2000}, :increase, 1_000)
    assert range == [{0, 10}, {1000, 30}]
  end

  # -------------------------------------------------------
  # :rate (reset-aware)
  # -------------------------------------------------------

  test "rate is per-second reset-aware increase", %{db: db} do
    # increase = 60; elapsed = (500-0)/1000 = 0.5s; rate = 120.0
    :ok = CounterTSDB.insert(db, "reqs", %{}, 0, 100)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 500, 160)

    [{_labels, [{0, rate}]}] = CounterTSDB.query_range(db, "reqs", %{}, {0, 1000}, :rate, 1_000)
    assert_in_delta rate, 120.0, 0.01
  end

  test "rate accounts for a reset within the window", %{db: db} do
    # values 10,15,5,8 at 0,100,200,300 -> increase 13; elapsed (300-0)/1000=0.3
    # rate = 13 / 0.3 = 43.333...
    :ok = CounterTSDB.insert(db, "reqs", %{}, 0, 10)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 100, 15)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 200, 5)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 300, 8)

    [{_labels, [{0, rate}]}] = CounterTSDB.query_range(db, "reqs", %{}, {0, 1000}, :rate, 1_000)
    assert_in_delta rate, 43.3333, 0.01
  end

  test "rate omits windows with fewer than 2 points", %{db: db} do
    :ok = CounterTSDB.insert(db, "reqs", %{}, 100, 5)
    assert [] = CounterTSDB.query_range(db, "reqs", %{}, {0, 1000}, :rate, 1_000)
  end

  test "rate omits a zero-elapsed window but keeps the other windows", %{db: db} do
    # window [0,1000): two points sharing timestamp 100 -> last == first -> omitted
    :ok = CounterTSDB.insert(db, "reqs", %{}, 100, 5)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 100, 9)
    # window [1000,2000): increase 50 over (1600-1100)/1000 = 0.5s -> 100.0
    :ok = CounterTSDB.insert(db, "reqs", %{}, 1100, 10)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 1600, 60)

    [{_labels, [{1000, rate}]}] =
      CounterTSDB.query_range(db, "reqs", %{}, {0, 2000}, :rate, 1_000)

    assert_in_delta rate, 100.0, 0.01
  end

  # -------------------------------------------------------
  # Duplicate timestamps are both retained
  # -------------------------------------------------------

  test "query returns both points inserted at the same timestamp", %{db: db} do
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "a"}, 100, 5)
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "a"}, 100, 9)
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "a"}, 200, 20)

    [{%{"i" => "a"}, points}] = CounterTSDB.query(db, "reqs", %{"i" => "a"}, {0, 500})

    # Both duplicate-timestamp samples survive, and the list stays sorted by
    # timestamp, so the pair at 100 precedes the point at 200.
    assert length(points) == 3
    assert Enum.map(points, fn {ts, _v} -> ts end) == [100, 100, 200]
    assert Enum.sort(points) == [{100, 5}, {100, 9}, {200, 20}]
  end

  test "increase counts a duplicate-timestamp pair as two points", %{db: db} do
    # Two samples share timestamp 100 and carry equal values, so whatever their
    # relative order the window holds 2 points and contributes a delta of 0.
    # A store that collapsed them would leave 1 point and omit the window.
    :ok = CounterTSDB.insert(db, "reqs", %{}, 100, 7)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 100, 7)

    [{_labels, range}] = CounterTSDB.query_range(db, "reqs", %{}, {0, 1000}, :increase, 1_000)
    assert range == [{0, 0}]
  end

  # -------------------------------------------------------
  # Label matching / multiple series
  # -------------------------------------------------------

  test "range query returns separate results per matched series", %{db: db} do
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "a"}, 0, 0)
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "a"}, 500, 10)
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "b"}, 0, 0)
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "b"}, 500, 40)

    result = CounterTSDB.query_range(db, "reqs", %{}, {0, 1000}, :increase, 1_000)
    assert length(result) == 2

    incs =
      result
      |> Enum.map(fn {labels, [{0, inc}]} -> {labels["i"], inc} end)
      |> Enum.sort()

    assert incs == [{"a", 10}, {"b", 40}]
  end

  test "label matchers select series containing all specified labels", %{db: db} do
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "a", "env" => "prod"}, 0, 0)
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "a", "env" => "prod"}, 500, 10)
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "b", "env" => "dev"}, 0, 0)
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "b", "env" => "dev"}, 500, 99)

    result = CounterTSDB.query_range(db, "reqs", %{"env" => "prod"}, {0, 1000}, :increase, 1_000)
    assert [{%{"env" => "prod"}, [{0, 10}]}] = result
  end

  test "label order does not create duplicate series", %{db: db} do
    :ok = CounterTSDB.insert(db, "reqs", %{"a" => "1", "b" => "2"}, 0, 0)
    :ok = CounterTSDB.insert(db, "reqs", %{"b" => "2", "a" => "1"}, 500, 20)

    [{_labels, [{0, inc}]}] =
      CounterTSDB.query_range(db, "reqs", %{"a" => "1", "b" => "2"}, {0, 1000}, :increase, 1_000)

    assert inc == 20
  end

  # -------------------------------------------------------
  # Cleanup
  # -------------------------------------------------------

  test "cleanup removes expired chunks", %{db: db} do
    :ok = CounterTSDB.insert(db, "reqs", %{}, 100, 1)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 5000, 2)

    Clock.set(12_000)
    send(db, :cleanup)

    # A subsequent public call is processed after :cleanup (FIFO mailbox),
    # so the query observes the post-cleanup state without touching internals.
    [{_labels, points}] = CounterTSDB.query(db, "reqs", %{}, {0, 20_000})
    assert points == [{5000, 2}]
  end

  test "cleanup removes a series with no remaining chunks", %{db: db} do
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "a"}, 100, 1)

    Clock.set(100_000)
    send(db, :cleanup)

    # The query below is handled after the :cleanup message, so it reflects
    # the cleaned-up state through the public API alone.
    assert [] = CounterTSDB.query(db, "reqs", %{"i" => "a"}, {0, 200_000})
  end

  test "cleanup runs on its own repeatedly on the cleanup interval" do
    test_pid = self()

    # The injected clock is only consulted by cleanup, so each read announces
    # that a cleanup pass ran without the test ever sending :cleanup itself.
    clock = fn ->
      send(test_pid, :cleanup_ran)
      1_000_000
    end

    {:ok, db} =
      CounterTSDB.start_link(
        clock: clock,
        chunk_duration_ms: 1_000,
        retention_ms: 10_000,
        cleanup_interval_ms: 25
      )

    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "a"}, 100, 1)

    # Two unsolicited passes: cleanup is scheduled again after it runs.
    assert_receive :cleanup_ran, 2_000
    assert_receive :cleanup_ran, 2_000

    # The chunk holding the point expired long before the clock's 1_000_000,
    # so the automatic pass dropped both the chunk and its now-empty series.
    assert [] = CounterTSDB.query(db, "reqs", %{"i" => "a"}, {0, 2_000_000})
  end

  test "increase treats an equal consecutive value as a zero delta, not a reset", %{db: db} do
    # values 10, 10, 15 -> deltas 0 (10 >= 10, no reset), 5 -> total 5
    :ok = CounterTSDB.insert(db, "reqs", %{}, 0, 10)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 100, 10)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 200, 15)

    [{_labels, range}] = CounterTSDB.query_range(db, "reqs", %{}, {0, 1000}, :increase, 1_000)
    assert range == [{0, 5}]
  end

  test "cleanup drops a chunk whose end exactly equals the retention threshold", %{db: db} do
    # chunk_duration_ms 1_000, retention_ms 10_000.
    :ok = CounterTSDB.insert(db, "reqs", %{}, 100, 1)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 1_000, 2)

    # now - retention_ms = 1_000. Chunk 0 ends at 0 + 1_000 == 1_000 -> removed.
    # Chunk 1_000 ends at 2_000 > 1_000 -> kept.
    Clock.set(11_000)
    send(db, :cleanup)

    [{_labels, points}] = CounterTSDB.query(db, "reqs", %{}, {0, 20_000})
    assert points == [{1_000, 2}]
  end

  test "retention defaults to one hour when the option is omitted" do
    {:ok, db} =
      CounterTSDB.start_link(
        clock: &Clock.now/0,
        chunk_duration_ms: 1_000,
        cleanup_interval_ms: :infinity
      )

    :ok = CounterTSDB.insert(db, "reqs", %{}, 0, 1)

    # threshold = 100_000 - 3_600_000 < 0, so the chunk survives.
    Clock.set(100_000)
    send(db, :cleanup)
    [{_labels, points}] = CounterTSDB.query(db, "reqs", %{}, {0, 10_000})
    assert points == [{0, 1}]

    # threshold = 3_601_000 - 3_600_000 = 1_000; chunk ends at 1_000 -> expired.
    Clock.set(3_601_000)
    send(db, :cleanup)
    assert [] = CounterTSDB.query(db, "reqs", %{}, {0, 10_000})
  end

  test "chunk duration defaults to sixty seconds when the option is omitted" do
    {:ok, db} =
      CounterTSDB.start_link(
        clock: &Clock.now/0,
        retention_ms: 10_000,
        cleanup_interval_ms: :infinity
      )

    :ok = CounterTSDB.insert(db, "reqs", %{}, 0, 1)

    # threshold = 20_000 - 10_000 = 10_000; the default chunk ends at
    # 0 + 60_000 = 60_000 > 10_000, so the point must survive cleanup.
    Clock.set(20_000)
    send(db, :cleanup)

    [{_labels, points}] = CounterTSDB.query(db, "reqs", %{}, {0, 10_000})
    assert points == [{0, 1}]
  end

  test "the name option registers the process for public API calls" do
    {:ok, _pid} =
      CounterTSDB.start_link(
        name: :counter_tsdb_named_test,
        clock: &Clock.now/0,
        chunk_duration_ms: 1_000,
        cleanup_interval_ms: :infinity
      )

    :ok = CounterTSDB.insert(:counter_tsdb_named_test, "reqs", %{"i" => "a"}, 100, 5)
    :ok = CounterTSDB.insert(:counter_tsdb_named_test, "reqs", %{"i" => "a"}, 200, 9)

    assert [{%{"i" => "a"}, [{100, 5}, {200, 9}]}] =
             CounterTSDB.query(:counter_tsdb_named_test, "reqs", %{"i" => "a"}, {0, 500})
  end

  test "query returns an empty list when neither metric nor matchers select a series", %{db: db} do
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "a"}, 100, 10)

    assert [] == CounterTSDB.query(db, "other_metric", %{}, {0, 500})
    assert [] == CounterTSDB.query(db, "reqs", %{"i" => "z"}, {0, 500})
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
