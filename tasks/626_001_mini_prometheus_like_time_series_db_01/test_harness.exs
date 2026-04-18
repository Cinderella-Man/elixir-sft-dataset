defmodule TSDBTest do
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
      TSDB.start_link(
        clock: &Clock.now/0,
        chunk_duration_ms: 1_000,
        retention_ms: 10_000,
        cleanup_interval_ms: :infinity
      )

    %{db: pid}
  end

  # -------------------------------------------------------
  # Basic insert and query
  # -------------------------------------------------------

  test "insert and retrieve a single data point", %{db: db} do
    assert :ok = TSDB.insert(db, "cpu", %{"host" => "a"}, 100, 0.5)

    result = TSDB.query(db, "cpu", %{"host" => "a"}, {0, 200})
    assert [{%{"host" => "a"}, [{100, 0.5}]}] = result
  end

  test "multiple points in the same series are sorted by timestamp", %{db: db} do
    :ok = TSDB.insert(db, "cpu", %{"host" => "a"}, 300, 0.3)
    :ok = TSDB.insert(db, "cpu", %{"host" => "a"}, 100, 0.1)
    :ok = TSDB.insert(db, "cpu", %{"host" => "a"}, 200, 0.2)

    [{_labels, points}] = TSDB.query(db, "cpu", %{"host" => "a"}, {0, 500})
    assert points == [{100, 0.1}, {200, 0.2}, {300, 0.3}]
  end

  test "query filters by time range (inclusive bounds)", %{db: db} do
    for ts <- [100, 200, 300, 400, 500] do
      :ok = TSDB.insert(db, "m", %{}, ts, ts * 1.0)
    end

    [{_labels, points}] = TSDB.query(db, "m", %{}, {200, 400})
    timestamps = Enum.map(points, &elem(&1, 0))
    assert timestamps == [200, 300, 400]
  end

  test "query returns empty list when no data matches", %{db: db} do
    :ok = TSDB.insert(db, "m", %{"a" => "1"}, 100, 1)

    assert [] = TSDB.query(db, "m", %{"a" => "1"}, {500, 600})
    assert [] = TSDB.query(db, "other_metric", %{}, {0, 1000})
  end

  # -------------------------------------------------------
  # Label matching
  # -------------------------------------------------------

  test "label matchers select series that contain all specified labels", %{db: db} do
    :ok = TSDB.insert(db, "http", %{"method" => "GET", "status" => "200"}, 100, 1)
    :ok = TSDB.insert(db, "http", %{"method" => "POST", "status" => "200"}, 100, 2)
    :ok = TSDB.insert(db, "http", %{"method" => "GET", "status" => "500"}, 100, 3)

    # Match only status=200
    result = TSDB.query(db, "http", %{"status" => "200"}, {0, 200})
    assert length(result) == 2

    values =
      result |> Enum.flat_map(fn {_, pts} -> Enum.map(pts, &elem(&1, 1)) end) |> Enum.sort()

    assert values == [1, 2]
  end

  test "empty label matcher matches all series for that metric", %{db: db} do
    :ok = TSDB.insert(db, "http", %{"method" => "GET"}, 100, 1)
    :ok = TSDB.insert(db, "http", %{"method" => "POST"}, 100, 2)

    result = TSDB.query(db, "http", %{}, {0, 200})
    assert length(result) == 2
  end

  test "label order does not create duplicate series", %{db: db} do
    # These should go into the same series regardless of map key ordering
    :ok = TSDB.insert(db, "m", %{"a" => "1", "b" => "2"}, 100, 10)
    :ok = TSDB.insert(db, "m", %{"b" => "2", "a" => "1"}, 200, 20)

    result = TSDB.query(db, "m", %{"a" => "1", "b" => "2"}, {0, 300})
    assert length(result) == 1
    [{_labels, points}] = result
    assert points == [{100, 10}, {200, 20}]
  end

  # -------------------------------------------------------
  # Chunked storage
  # -------------------------------------------------------

  test "data points span multiple chunks correctly", %{db: db} do
    # chunk_duration_ms = 1_000, so chunk boundaries at 0, 1000, 2000 ...
    :ok = TSDB.insert(db, "m", %{}, 500, 1)
    :ok = TSDB.insert(db, "m", %{}, 1500, 2)
    :ok = TSDB.insert(db, "m", %{}, 2500, 3)

    [{_labels, points}] = TSDB.query(db, "m", %{}, {0, 3000})
    assert points == [{500, 1}, {1500, 2}, {2500, 3}]
  end

  test "querying a sub-range only returns points from relevant chunks", %{db: db} do
    :ok = TSDB.insert(db, "m", %{}, 500, 1)
    :ok = TSDB.insert(db, "m", %{}, 1500, 2)
    :ok = TSDB.insert(db, "m", %{}, 2500, 3)

    [{_labels, points}] = TSDB.query(db, "m", %{}, {1000, 2000})
    assert points == [{1500, 2}]
  end

  # -------------------------------------------------------
  # Aggregation: :sum
  # -------------------------------------------------------

  test "query_agg :sum computes the sum per window", %{db: db} do
    # Insert points: step_ms = 1000
    # Window [0, 1000): timestamps 100, 200, 300
    :ok = TSDB.insert(db, "m", %{}, 100, 10)
    :ok = TSDB.insert(db, "m", %{}, 200, 20)
    :ok = TSDB.insert(db, "m", %{}, 300, 30)
    # Window [1000, 2000): timestamps 1100, 1500
    :ok = TSDB.insert(db, "m", %{}, 1100, 5)
    :ok = TSDB.insert(db, "m", %{}, 1500, 15)

    [{_labels, agg_points}] = TSDB.query_agg(db, "m", %{}, {0, 2000}, :sum, 1_000)

    assert agg_points == [{0, 60}, {1000, 20}]
  end

  # -------------------------------------------------------
  # Aggregation: :avg
  # -------------------------------------------------------

  test "query_agg :avg computes the mean per window", %{db: db} do
    :ok = TSDB.insert(db, "m", %{}, 100, 10)
    :ok = TSDB.insert(db, "m", %{}, 200, 20)
    :ok = TSDB.insert(db, "m", %{}, 300, 30)

    [{_labels, agg_points}] = TSDB.query_agg(db, "m", %{}, {0, 1000}, :avg, 1_000)

    [{0, avg_value}] = agg_points
    assert_in_delta avg_value, 20.0, 0.01
  end

  # -------------------------------------------------------
  # Aggregation: :max
  # -------------------------------------------------------

  test "query_agg :max returns the maximum value per window", %{db: db} do
    :ok = TSDB.insert(db, "m", %{}, 100, 10)
    :ok = TSDB.insert(db, "m", %{}, 200, 50)
    :ok = TSDB.insert(db, "m", %{}, 300, 30)

    [{_labels, agg_points}] = TSDB.query_agg(db, "m", %{}, {0, 1000}, :max, 1_000)

    assert agg_points == [{0, 50}]
  end

  # -------------------------------------------------------
  # Aggregation: :rate
  # -------------------------------------------------------

  test "query_agg :rate computes per-second rate of change", %{db: db} do
    # Window [0, 1000): value goes from 100 at t=0 to 200 at t=500
    # rate = (200 - 100) / ((500 - 0) / 1000) = 100 / 0.5 = 200.0
    :ok = TSDB.insert(db, "m", %{}, 0, 100)
    :ok = TSDB.insert(db, "m", %{}, 500, 200)

    [{_labels, agg_points}] = TSDB.query_agg(db, "m", %{}, {0, 1000}, :rate, 1_000)

    [{0, rate}] = agg_points
    assert_in_delta rate, 200.0, 0.01
  end

  test "query_agg :rate omits windows with fewer than 2 points", %{db: db} do
    # Window [0, 1000): only 1 point — should be omitted
    :ok = TSDB.insert(db, "m", %{}, 100, 42)
    # Window [1000, 2000): 2 points — should be included
    :ok = TSDB.insert(db, "m", %{}, 1100, 10)
    :ok = TSDB.insert(db, "m", %{}, 1600, 60)

    [{_labels, agg_points}] = TSDB.query_agg(db, "m", %{}, {0, 2000}, :rate, 1_000)

    # Only the second window
    assert length(agg_points) == 1
    [{1000, rate}] = agg_points
    # (60 - 10) / ((1600 - 1100) / 1000) = 50 / 0.5 = 100.0
    assert_in_delta rate, 100.0, 0.01
  end

  # -------------------------------------------------------
  # Aggregation: empty windows are omitted
  # -------------------------------------------------------

  test "query_agg omits windows with no data points", %{db: db} do
    # Points only in window [0, 1000), nothing in [1000, 2000)
    :ok = TSDB.insert(db, "m", %{}, 100, 1)
    :ok = TSDB.insert(db, "m", %{}, 200, 2)

    [{_labels, agg_points}] = TSDB.query_agg(db, "m", %{}, {0, 2000}, :sum, 1_000)

    assert agg_points == [{0, 3}]
  end

  # -------------------------------------------------------
  # Aggregation: multiple series
  # -------------------------------------------------------

  test "query_agg returns separate aggregations per matched series", %{db: db} do
    :ok = TSDB.insert(db, "cpu", %{"host" => "a"}, 100, 10)
    :ok = TSDB.insert(db, "cpu", %{"host" => "a"}, 200, 20)
    :ok = TSDB.insert(db, "cpu", %{"host" => "b"}, 100, 100)
    :ok = TSDB.insert(db, "cpu", %{"host" => "b"}, 200, 200)

    result = TSDB.query_agg(db, "cpu", %{}, {0, 1000}, :sum, 1_000)

    assert length(result) == 2

    sums =
      result
      |> Enum.map(fn {labels, [{0, sum}]} -> {labels["host"], sum} end)
      |> Enum.sort()

    assert sums == [{"a", 30}, {"b", 300}]
  end

  # -------------------------------------------------------
  # Aggregation: step boundaries
  # -------------------------------------------------------

  test "query_agg correctly buckets across multiple step windows", %{db: db} do
    # step_ms = 500, range [0, 2000)
    # Window [0, 500): t=100 v=1, t=200 v=2
    :ok = TSDB.insert(db, "m", %{}, 100, 1)
    :ok = TSDB.insert(db, "m", %{}, 200, 2)
    # Window [500, 1000): t=600 v=10
    :ok = TSDB.insert(db, "m", %{}, 600, 10)
    # Window [1000, 1500): empty
    # Window [1500, 2000): t=1700 v=99
    :ok = TSDB.insert(db, "m", %{}, 1700, 99)

    [{_labels, agg_points}] = TSDB.query_agg(db, "m", %{}, {0, 2000}, :sum, 500)

    assert agg_points == [{0, 3}, {500, 10}, {1500, 99}]
  end

  # -------------------------------------------------------
  # Cleanup
  # -------------------------------------------------------

  test "cleanup removes expired chunks", %{db: db} do
    # retention_ms = 10_000, chunk_duration_ms = 1_000
    # Insert at t=100 → chunk_start=0, expires when now > 0 + 1000 + 10_000 = 11_000
    :ok = TSDB.insert(db, "m", %{}, 100, 1)
    # Insert at t=5000 → chunk_start=5000, expires when now > 5000 + 1000 + 10_000 = 16_000
    :ok = TSDB.insert(db, "m", %{}, 5000, 2)

    # At time 12_000, the first chunk is expired but the second is not
    Clock.set(12_000)
    send(db, :cleanup)
    :sys.get_state(db)

    result = TSDB.query(db, "m", %{}, {0, 20_000})
    [{_labels, points}] = result
    assert points == [{5000, 2}]
  end

  test "cleanup removes series with no remaining chunks", %{db: db} do
    :ok = TSDB.insert(db, "m", %{"host" => "a"}, 100, 1)

    # Advance well past retention
    Clock.set(100_000)
    send(db, :cleanup)
    :sys.get_state(db)

    # Series should be gone entirely
    assert [] = TSDB.query(db, "m", %{"host" => "a"}, {0, 200_000})

    # Verify internal state is clean
    state = :sys.get_state(db)
    assert map_size(state.series) == 0
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "insert and query with empty labels", %{db: db} do
    :ok = TSDB.insert(db, "m", %{}, 100, 42)

    [{labels, [{100, 42}]}] = TSDB.query(db, "m", %{}, {0, 200})
    assert labels == %{}
  end

  test "query_agg with no matching data returns empty list", %{db: db} do
    assert [] = TSDB.query_agg(db, "nonexistent", %{}, {0, 1000}, :sum, 500)
  end

  test "inserting integer and float values both work", %{db: db} do
    :ok = TSDB.insert(db, "m", %{}, 100, 42)
    :ok = TSDB.insert(db, "m", %{}, 200, 3.14)

    [{_labels, points}] = TSDB.query(db, "m", %{}, {0, 300})
    assert points == [{100, 42}, {200, 3.14}]
  end

  test "points exactly on chunk boundaries go into the correct chunk", %{db: db} do
    # chunk_duration_ms = 1_000
    # t=1000 should go into chunk_start=1000, not chunk_start=0
    :ok = TSDB.insert(db, "m", %{}, 999, 1)
    :ok = TSDB.insert(db, "m", %{}, 1000, 2)
    :ok = TSDB.insert(db, "m", %{}, 1001, 3)

    # Query only chunk [1000, 2000)
    [{_labels, points}] = TSDB.query(db, "m", %{}, {1000, 1999})
    assert points == [{1000, 2}, {1001, 3}]
  end
end
