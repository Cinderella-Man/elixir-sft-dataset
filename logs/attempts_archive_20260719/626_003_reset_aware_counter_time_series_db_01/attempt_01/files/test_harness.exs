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
end
