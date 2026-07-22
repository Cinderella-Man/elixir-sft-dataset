defmodule ShardedTSDBTest do
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
      ShardedTSDB.start_link(
        shards: 4,
        clock: &Clock.now/0,
        chunk_duration_ms: 1_000,
        retention_ms: 10_000,
        cleanup_interval_ms: :infinity
      )

    %{db: pid}
  end

  # -------------------------------------------------------
  # Basic insert / query
  # -------------------------------------------------------

  test "insert returns :ok and query retrieves the point", %{db: db} do
    assert :ok = ShardedTSDB.insert(db, "cpu", %{"host" => "a"}, 100, 0.5)

    result = ShardedTSDB.query(db, "cpu", %{"host" => "a"}, {0, 200})
    assert [{%{"host" => "a"}, [{100, 0.5}]}] = result
  end

  test "points in one series are returned sorted by timestamp", %{db: db} do
    :ok = ShardedTSDB.insert(db, "cpu", %{"host" => "a"}, 300, 0.3)
    :ok = ShardedTSDB.insert(db, "cpu", %{"host" => "a"}, 100, 0.1)
    :ok = ShardedTSDB.insert(db, "cpu", %{"host" => "a"}, 200, 0.2)

    [{_labels, points}] = ShardedTSDB.query(db, "cpu", %{"host" => "a"}, {0, 500})
    assert points == [{100, 0.1}, {200, 0.2}, {300, 0.3}]
  end

  test "query fans out and merges across many series", %{db: db} do
    for h <- ["a", "b", "c", "d", "e", "f"] do
      :ok = ShardedTSDB.insert(db, "cpu", %{"host" => h}, 100, 1)
    end

    result = ShardedTSDB.query(db, "cpu", %{}, {0, 200})
    hosts = result |> Enum.map(fn {labels, _} -> labels["host"] end) |> Enum.sort()
    assert hosts == ["a", "b", "c", "d", "e", "f"]
  end

  test "query filters by inclusive time range", %{db: db} do
    for ts <- [100, 200, 300, 400, 500] do
      :ok = ShardedTSDB.insert(db, "m", %{}, ts, ts * 1.0)
    end

    [{_labels, points}] = ShardedTSDB.query(db, "m", %{}, {200, 400})
    assert Enum.map(points, &elem(&1, 0)) == [200, 300, 400]
  end

  test "query includes points exactly at both range endpoints", %{db: db} do
    for ts <- [100, 200, 300] do
      :ok = ShardedTSDB.insert(db, "m", %{}, ts, ts)
    end

    [{_labels, points}] = ShardedTSDB.query(db, "m", %{}, {100, 300})
    assert points == [{100, 100}, {200, 200}, {300, 300}]
  end

  test "query omits series with no point in range and unknown metric", %{db: db} do
    :ok = ShardedTSDB.insert(db, "m", %{"a" => "1"}, 100, 1)
    assert [] = ShardedTSDB.query(db, "m", %{"a" => "1"}, {500, 600})
    assert [] = ShardedTSDB.query(db, "other", %{}, {0, 1000})
  end

  test "query merges points spanning multiple chunks sorted by timestamp", %{db: db} do
    :ok = ShardedTSDB.insert(db, "m", %{}, 1500, 2)
    :ok = ShardedTSDB.insert(db, "m", %{}, 500, 1)
    :ok = ShardedTSDB.insert(db, "m", %{}, 900, 3)
    :ok = ShardedTSDB.insert(db, "m", %{}, 2400, 4)

    [{_labels, points}] = ShardedTSDB.query(db, "m", %{}, {0, 5000})
    assert points == [{500, 1}, {900, 3}, {1500, 2}, {2400, 4}]
  end

  # -------------------------------------------------------
  # Label matching
  # -------------------------------------------------------

  test "label matchers select series containing all specified labels", %{db: db} do
    :ok = ShardedTSDB.insert(db, "http", %{"method" => "GET", "status" => "200"}, 100, 1)
    :ok = ShardedTSDB.insert(db, "http", %{"method" => "POST", "status" => "200"}, 100, 2)
    :ok = ShardedTSDB.insert(db, "http", %{"method" => "GET", "status" => "500"}, 100, 3)

    result = ShardedTSDB.query(db, "http", %{"status" => "200"}, {0, 200})
    assert length(result) == 2
  end

  test "label matchers requiring an unmatched value return nothing", %{db: db} do
    :ok = ShardedTSDB.insert(db, "http", %{"method" => "GET"}, 100, 1)
    :ok = ShardedTSDB.insert(db, "http", %{"method" => "PUT"}, 100, 2)

    assert [] = ShardedTSDB.query(db, "http", %{"method" => "DELETE"}, {0, 200})
  end

  test "label order does not create duplicate series", %{db: db} do
    :ok = ShardedTSDB.insert(db, "m", %{"a" => "1", "b" => "2"}, 100, 10)
    :ok = ShardedTSDB.insert(db, "m", %{"b" => "2", "a" => "1"}, 200, 20)

    result = ShardedTSDB.query(db, "m", %{"a" => "1", "b" => "2"}, {0, 300})
    assert length(result) == 1
    [{_labels, points}] = result
    assert points == [{100, 10}, {200, 20}]
  end

  test "same labels under different metrics are distinct series", %{db: db} do
    :ok = ShardedTSDB.insert(db, "cpu", %{"host" => "a"}, 100, 1)
    :ok = ShardedTSDB.insert(db, "mem", %{"host" => "a"}, 100, 2)

    assert ShardedTSDB.series_count(db) == 2
    assert [{_, [{100, 1}]}] = ShardedTSDB.query(db, "cpu", %{"host" => "a"}, {0, 200})
    assert [{_, [{100, 2}]}] = ShardedTSDB.query(db, "mem", %{"host" => "a"}, {0, 200})
  end

  # -------------------------------------------------------
  # Sharding introspection
  # -------------------------------------------------------

  test "shard_count returns the configured number of shards", %{db: db} do
    assert ShardedTSDB.shard_count(db) == 4
  end

  test "default options start four shards", _ctx do
    {:ok, db} = ShardedTSDB.start_link([])
    assert ShardedTSDB.shard_count(db) == 4
  end

  test "coordinator can be registered under a name", _ctx do
    {:ok, _pid} = ShardedTSDB.start_link(name: :named_tsdb, shards: 3)
    assert ShardedTSDB.shard_count(:named_tsdb) == 3
    assert :ok = ShardedTSDB.insert(:named_tsdb, "m", %{}, 100, 1)
    assert [{_, [{100, 1}]}] = ShardedTSDB.query(:named_tsdb, "m", %{}, {0, 200})
  end

  test "shard_of returns the documented phash2-based index", %{db: db} do
    expected = :erlang.phash2({"cpu", Enum.sort(Map.to_list(%{"host" => "a"}))}, 4)
    assert ShardedTSDB.shard_of(db, "cpu", %{"host" => "a"}) == expected
    assert ShardedTSDB.shard_of(db, "cpu", %{"host" => "a"}) in 0..3
  end

  test "shard_of is independent of label map ordering", %{db: db} do
    a = ShardedTSDB.shard_of(db, "m", %{"a" => "1", "b" => "2"})
    b = ShardedTSDB.shard_of(db, "m", %{"b" => "2", "a" => "1"})
    assert a == b
  end

  test "every shard_of index falls within the shard range", %{db: db} do
    for i <- 1..50 do
      idx = ShardedTSDB.shard_of(db, "cpu", %{"host" => "host-#{i}"})
      assert idx in 0..3
    end
  end

  test "series_count is zero before any insert", %{db: db} do
    assert ShardedTSDB.series_count(db) == 0
  end

  test "series_count reports distinct series across all shards", %{db: db} do
    :ok = ShardedTSDB.insert(db, "cpu", %{"host" => "a"}, 100, 1)
    :ok = ShardedTSDB.insert(db, "cpu", %{"host" => "b"}, 100, 1)
    :ok = ShardedTSDB.insert(db, "mem", %{"host" => "a"}, 100, 1)
    # Re-inserting into an existing series must not increase the count.
    :ok = ShardedTSDB.insert(db, "cpu", %{"host" => "a"}, 200, 2)

    assert ShardedTSDB.series_count(db) == 3
  end

  # -------------------------------------------------------
  # Aggregation
  # -------------------------------------------------------

  test "query_agg :sum computes the sum per window", %{db: db} do
    :ok = ShardedTSDB.insert(db, "m", %{}, 100, 10)
    :ok = ShardedTSDB.insert(db, "m", %{}, 200, 20)
    :ok = ShardedTSDB.insert(db, "m", %{}, 300, 30)
    :ok = ShardedTSDB.insert(db, "m", %{}, 1100, 5)
    :ok = ShardedTSDB.insert(db, "m", %{}, 1500, 15)

    [{_labels, agg}] = ShardedTSDB.query_agg(db, "m", %{}, {0, 2000}, :sum, 1_000)
    assert agg == [{0, 60}, {1000, 20}]
  end

  test "query_agg :avg computes the mean per window", %{db: db} do
    :ok = ShardedTSDB.insert(db, "m", %{}, 100, 10)
    :ok = ShardedTSDB.insert(db, "m", %{}, 200, 20)
    :ok = ShardedTSDB.insert(db, "m", %{}, 300, 30)

    [{_labels, [{0, avg}]}] = ShardedTSDB.query_agg(db, "m", %{}, {0, 1000}, :avg, 1_000)
    assert_in_delta avg, 20.0, 0.01
  end

  test "query_agg :avg produces a mean per window across windows", %{db: db} do
    :ok = ShardedTSDB.insert(db, "m", %{}, 100, 10)
    :ok = ShardedTSDB.insert(db, "m", %{}, 200, 20)
    :ok = ShardedTSDB.insert(db, "m", %{}, 1100, 40)

    [{_labels, agg}] = ShardedTSDB.query_agg(db, "m", %{}, {0, 2000}, :avg, 1_000)
    assert agg == [{0, 15.0}, {1000, 40.0}]
  end

  test "query_agg :max returns the maximum per window", %{db: db} do
    :ok = ShardedTSDB.insert(db, "m", %{}, 100, 10)
    :ok = ShardedTSDB.insert(db, "m", %{}, 200, 50)
    :ok = ShardedTSDB.insert(db, "m", %{}, 300, 30)

    [{_labels, agg}] = ShardedTSDB.query_agg(db, "m", %{}, {0, 1000}, :max, 1_000)
    assert agg == [{0, 50}]
  end

  test "query_agg :max reports the maximum per window across windows", %{db: db} do
    :ok = ShardedTSDB.insert(db, "m", %{}, 100, 10)
    :ok = ShardedTSDB.insert(db, "m", %{}, 600, 50)
    :ok = ShardedTSDB.insert(db, "m", %{}, 1200, 5)

    [{_labels, agg}] = ShardedTSDB.query_agg(db, "m", %{}, {0, 2000}, :max, 1_000)
    assert agg == [{0, 50}, {1000, 5}]
  end

  test "query_agg treats the end of the range as exclusive", %{db: db} do
    :ok = ShardedTSDB.insert(db, "m", %{}, 500, 5)
    :ok = ShardedTSDB.insert(db, "m", %{}, 1000, 10)

    [{_labels, agg}] = ShardedTSDB.query_agg(db, "m", %{}, {0, 1000}, :sum, 1_000)
    assert agg == [{0, 5}]
  end

  test "query_agg on an unknown metric returns an empty list", %{db: db} do
    assert [] = ShardedTSDB.query_agg(db, "nope", %{}, {0, 1000}, :sum, 1_000)
  end

  test "query_agg omits empty windows and returns per-series results", %{db: db} do
    :ok = ShardedTSDB.insert(db, "cpu", %{"host" => "a"}, 100, 10)
    :ok = ShardedTSDB.insert(db, "cpu", %{"host" => "a"}, 200, 20)
    :ok = ShardedTSDB.insert(db, "cpu", %{"host" => "b"}, 100, 100)

    result = ShardedTSDB.query_agg(db, "cpu", %{}, {0, 2000}, :sum, 1_000)
    assert length(result) == 2

    sums =
      result
      |> Enum.map(fn {labels, agg} -> {labels["host"], agg} end)
      |> Enum.sort()

    assert sums == [{"a", [{0, 30}]}, {"b", [{0, 100}]}]
  end

  # -------------------------------------------------------
  # Cleanup
  # -------------------------------------------------------

  test "cleanup removes expired chunks across shards", %{db: db} do
    :ok = ShardedTSDB.insert(db, "m", %{}, 100, 1)
    :ok = ShardedTSDB.insert(db, "m", %{}, 5000, 2)

    Clock.set(12_000)
    assert :ok = ShardedTSDB.cleanup(db)

    [{_labels, points}] = ShardedTSDB.query(db, "m", %{}, {0, 20_000})
    assert points == [{5000, 2}]
  end

  test "cleanup applies the boundary rule at exactly the cutoff", %{db: db} do
    :ok = ShardedTSDB.insert(db, "m", %{}, 0, 1)
    :ok = ShardedTSDB.insert(db, "m", %{}, 1000, 2)

    # now - retention_ms == 1000; chunk ending at 1000 is dropped, one ending
    # at 2000 is kept.
    Clock.set(11_000)
    assert :ok = ShardedTSDB.cleanup(db)

    [{_labels, points}] = ShardedTSDB.query(db, "m", %{}, {0, 20_000})
    assert points == [{1000, 2}]
  end

  test "cleanup does not touch chunks that are still within retention", %{db: db} do
    :ok = ShardedTSDB.insert(db, "m", %{}, 100, 1)

    Clock.set(5_000)
    assert :ok = ShardedTSDB.cleanup(db)

    [{_labels, points}] = ShardedTSDB.query(db, "m", %{}, {0, 20_000})
    assert points == [{100, 1}]
    assert ShardedTSDB.series_count(db) == 1
  end

  test "cleanup drops series left with no chunks and updates series_count", %{db: db} do
    :ok = ShardedTSDB.insert(db, "m", %{"host" => "a"}, 100, 1)
    :ok = ShardedTSDB.insert(db, "m", %{"host" => "b"}, 8000, 1)

    Clock.set(12_000)
    assert :ok = ShardedTSDB.cleanup(db)

    assert [] = ShardedTSDB.query(db, "m", %{"host" => "a"}, {0, 200_000})
    assert ShardedTSDB.series_count(db) == 1
  end

  # -------------------------------------------------------
  # Periodic cleanup via the coordinator's handle_info/2
  # -------------------------------------------------------

  test "periodic :cleanup_tick message runs cleanup across shards", %{db: db} do
    :ok = ShardedTSDB.insert(db, "m", %{}, 100, 1)
    :ok = ShardedTSDB.insert(db, "m", %{}, 5000, 2)

    Clock.set(12_000)

    # Deliver the scheduled tick directly. The coordinator's handle_info/2
    # must apply the same retention rule as cleanup/1. A subsequent
    # synchronous call is queued behind this message, so it only returns
    # after the tick has been handled.
    send(db, :cleanup_tick)

    [{_labels, points}] = ShardedTSDB.query(db, "m", %{}, {0, 20_000})
    assert points == [{5000, 2}]
    assert ShardedTSDB.series_count(db) == 1
  end

  test "the coordinator survives and keeps serving after a tick", %{db: db} do
    :ok = ShardedTSDB.insert(db, "m", %{}, 100, 1)

    # A tick with the clock still at 0 must delete nothing and must not
    # crash the coordinator; it must keep answering calls afterwards.
    send(db, :cleanup_tick)

    assert ShardedTSDB.series_count(db) == 1
    [{_labels, points}] = ShardedTSDB.query(db, "m", %{}, {0, 20_000})
    assert points == [{100, 1}]

    # An unrelated info message must also be handled gracefully.
    send(db, :some_unrelated_message)
    assert ShardedTSDB.shard_count(db) == 4
  end

  test "an automatic tick fires and cleans when an interval is configured", _ctx do
    {:ok, db} =
      ShardedTSDB.start_link(
        shards: 2,
        clock: &Clock.now/0,
        chunk_duration_ms: 1_000,
        retention_ms: 10_000,
        cleanup_interval_ms: 20
      )

    :ok = ShardedTSDB.insert(db, "m", %{}, 100, 1)
    :ok = ShardedTSDB.insert(db, "m", %{}, 5000, 2)

    Clock.set(12_000)

    # Wait for the periodically-scheduled tick to fire and expire the old
    # chunk on its own (no manual cleanup/1 call).
    wait_until(fn ->
      case ShardedTSDB.query(db, "m", %{}, {0, 20_000}) do
        [{_labels, [{5000, 2}]}] -> true
        _ -> false
      end
    end)

    assert [{_labels, [{5000, 2}]}] = ShardedTSDB.query(db, "m", %{}, {0, 20_000})
  end

  defp wait_until(fun, attempts \\ 200) do
    cond do
      fun.() ->
        :ok

      attempts <= 0 ->
        flunk("condition was never met")

      true ->
        Process.sleep(10)
        wait_until(fun, attempts - 1)
    end
  end
end
