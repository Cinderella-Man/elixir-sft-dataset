defmodule RollupTSDBTest do
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
      RollupTSDB.start_link(
        clock: &Clock.now/0,
        bucket_duration_ms: 1_000,
        retention_ms: 10_000,
        cleanup_interval_ms: :infinity
      )

    %{db: pid}
  end

  # A `RollupTSDB.query/4` call is an ordinary message delivered to the same
  # process after a preceding `send(db, :cleanup)`; the GenServer processes its
  # mailbox in order, so once the query reply comes back the `:cleanup` has
  # already been handled. We observe cleanup effects purely through the public
  # query API rather than by inspecting internal state.
  defp sync_cleanup(db) do
    send(db, :cleanup)
    :ok
  end

  # -------------------------------------------------------
  # Basic rollup accumulation
  # -------------------------------------------------------

  test "insert returns :ok", %{db: db} do
    assert :ok = RollupTSDB.insert(db, "cpu", %{"host" => "a"}, 100, 0.5)
  end

  test "a single bucket accumulates count/sum/min/max/avg", %{db: db} do
    :ok = RollupTSDB.insert(db, "cpu", %{"host" => "a"}, 100, 10)
    :ok = RollupTSDB.insert(db, "cpu", %{"host" => "a"}, 200, 20)
    :ok = RollupTSDB.insert(db, "cpu", %{"host" => "a"}, 300, 30)

    [{%{"host" => "a"}, [{0, stats}]}] = RollupTSDB.query(db, "cpu", %{"host" => "a"}, {0, 900})

    assert stats.count == 3
    assert stats.sum == 60
    assert stats.min == 10
    assert stats.max == 30
    assert_in_delta stats.avg, 20.0, 0.0001
  end

  test "first is the value at the smallest timestamp, last at the largest", %{db: db} do
    # Insert out of order; first should track the earliest timestamp (100),
    # last should track the latest timestamp (300).
    :ok = RollupTSDB.insert(db, "m", %{}, 300, 30)
    :ok = RollupTSDB.insert(db, "m", %{}, 100, 10)
    :ok = RollupTSDB.insert(db, "m", %{}, 200, 20)

    [{_labels, [{0, stats}]}] = RollupTSDB.query(db, "m", %{}, {0, 900})
    assert stats.first == 10
    assert stats.last == 30
  end

  test "on a tie for the largest timestamp, the latest-arriving point wins for last", %{db: db} do
    :ok = RollupTSDB.insert(db, "m", %{}, 500, 1)
    :ok = RollupTSDB.insert(db, "m", %{}, 500, 2)

    [{_labels, [{0, stats}]}] = RollupTSDB.query(db, "m", %{}, {0, 900})
    assert stats.last == 2
    assert stats.first == 1
  end

  # -------------------------------------------------------
  # Multiple buckets
  # -------------------------------------------------------

  test "points fall into separate buckets by bucket_start", %{db: db} do
    # bucket_duration_ms = 1_000, boundaries at 0, 1000, 2000 ...
    :ok = RollupTSDB.insert(db, "m", %{}, 100, 1)
    :ok = RollupTSDB.insert(db, "m", %{}, 1100, 2)
    :ok = RollupTSDB.insert(db, "m", %{}, 1900, 8)

    [{_labels, buckets}] = RollupTSDB.query(db, "m", %{}, {0, 2000})
    starts = Enum.map(buckets, &elem(&1, 0))
    assert starts == [0, 1000]

    [{0, b0}, {1000, b1}] = buckets
    assert b0.sum == 1
    assert b1.sum == 10
    assert b1.count == 2
  end

  test "query restricts buckets to those with bucket_start in range (inclusive)", %{db: db} do
    :ok = RollupTSDB.insert(db, "m", %{}, 500, 1)
    :ok = RollupTSDB.insert(db, "m", %{}, 1500, 2)
    :ok = RollupTSDB.insert(db, "m", %{}, 2500, 3)

    [{_labels, buckets}] = RollupTSDB.query(db, "m", %{}, {1000, 2000})
    assert Enum.map(buckets, &elem(&1, 0)) == [1000, 2000]
  end

  # -------------------------------------------------------
  # Label matching
  # -------------------------------------------------------

  test "label matchers select series that contain all specified labels", %{db: db} do
    :ok = RollupTSDB.insert(db, "http", %{"method" => "GET", "status" => "200"}, 100, 1)
    :ok = RollupTSDB.insert(db, "http", %{"method" => "POST", "status" => "200"}, 100, 2)
    :ok = RollupTSDB.insert(db, "http", %{"method" => "GET", "status" => "500"}, 100, 3)

    result = RollupTSDB.query(db, "http", %{"status" => "200"}, {0, 900})
    assert length(result) == 2
  end

  test "empty label matcher matches all series for that metric", %{db: db} do
    :ok = RollupTSDB.insert(db, "http", %{"method" => "GET"}, 100, 1)
    :ok = RollupTSDB.insert(db, "http", %{"method" => "POST"}, 100, 2)

    assert length(RollupTSDB.query(db, "http", %{}, {0, 900})) == 2
  end

  test "label order does not create duplicate series", %{db: db} do
    :ok = RollupTSDB.insert(db, "m", %{"a" => "1", "b" => "2"}, 100, 10)
    :ok = RollupTSDB.insert(db, "m", %{"b" => "2", "a" => "1"}, 200, 20)

    result = RollupTSDB.query(db, "m", %{"a" => "1", "b" => "2"}, {0, 900})
    assert length(result) == 1
    [{_labels, [{0, stats}]}] = result
    assert stats.count == 2
    assert stats.sum == 30
  end

  # -------------------------------------------------------
  # Empty results
  # -------------------------------------------------------

  test "series with no buckets in range is omitted", %{db: db} do
    :ok = RollupTSDB.insert(db, "m", %{"a" => "1"}, 100, 1)
    assert [] = RollupTSDB.query(db, "m", %{"a" => "1"}, {5000, 6000})
  end

  test "unknown metric returns empty list", %{db: db} do
    :ok = RollupTSDB.insert(db, "m", %{}, 100, 1)
    assert [] = RollupTSDB.query(db, "other", %{}, {0, 10_000})
  end

  # -------------------------------------------------------
  # Cleanup
  # -------------------------------------------------------

  test "cleanup removes expired buckets but keeps fresh ones", %{db: db} do
    # retention_ms = 10_000, bucket_duration_ms = 1_000
    # bucket 0 expires when 0 + 1000 <= now - 10_000  -> now >= 11_000
    :ok = RollupTSDB.insert(db, "m", %{}, 100, 1)
    # bucket 5000 expires when 5000 + 1000 <= now - 10_000 -> now >= 16_000
    :ok = RollupTSDB.insert(db, "m", %{}, 5000, 2)

    Clock.set(12_000)
    :ok = sync_cleanup(db)

    [{_labels, buckets}] = RollupTSDB.query(db, "m", %{}, {0, 20_000})
    assert Enum.map(buckets, &elem(&1, 0)) == [5000]
  end

  test "cleanup removes a series left with no buckets", %{db: db} do
    :ok = RollupTSDB.insert(db, "m", %{"host" => "a"}, 100, 1)

    Clock.set(100_000)
    :ok = sync_cleanup(db)

    assert [] = RollupTSDB.query(db, "m", %{"host" => "a"}, {0, 200_000})
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "integer and float values both accumulate", %{db: db} do
    :ok = RollupTSDB.insert(db, "m", %{}, 100, 42)
    :ok = RollupTSDB.insert(db, "m", %{}, 200, 3.0)

    [{_labels, [{0, stats}]}] = RollupTSDB.query(db, "m", %{}, {0, 900})
    assert stats.count == 2
    assert_in_delta stats.sum, 45.0, 0.0001
  end

  test "points exactly on a bucket boundary go into the correct bucket", %{db: db} do
    :ok = RollupTSDB.insert(db, "m", %{}, 999, 1)
    :ok = RollupTSDB.insert(db, "m", %{}, 1000, 2)
    :ok = RollupTSDB.insert(db, "m", %{}, 1001, 3)

    [{_labels, buckets}] = RollupTSDB.query(db, "m", %{}, {0, 2000})
    starts = Enum.map(buckets, &elem(&1, 0))
    assert starts == [0, 1000]

    {1000, b1} = Enum.find(buckets, fn {bs, _} -> bs == 1000 end)
    assert b1.count == 2
    assert b1.sum == 5
  end

  test "stats map exposes exactly the documented keys and nothing else", %{db: db} do
    :ok = RollupTSDB.insert(db, "m", %{"host" => "a"}, 100, 5)
    :ok = RollupTSDB.insert(db, "m", %{"host" => "a"}, 200, 15)

    [{_labels, [{0, stats}]}] = RollupTSDB.query(db, "m", %{}, {0, 900})

    assert Enum.sort(Map.keys(stats)) == [:avg, :count, :first, :last, :max, :min, :sum]
    assert is_float(stats.avg)
  end

  test "a bucket is dropped exactly when start + duration equals now - retention", %{db: db} do
    # bucket 0 expires at now == 11_000; bucket 1000 expires at now == 12_000
    :ok = RollupTSDB.insert(db, "m", %{}, 100, 1)
    :ok = RollupTSDB.insert(db, "m", %{}, 1500, 2)

    Clock.set(10_999)
    :ok = sync_cleanup(db)
    [{_labels, buckets}] = RollupTSDB.query(db, "m", %{}, {0, 20_000})
    assert Enum.map(buckets, &elem(&1, 0)) == [0, 1000]

    Clock.set(11_000)
    :ok = sync_cleanup(db)
    [{_labels, kept}] = RollupTSDB.query(db, "m", %{}, {0, 20_000})
    assert Enum.map(kept, &elem(&1, 0)) == [1000]
  end

  test "automatic cleanup re-arms itself after each run" do
    test_pid = self()

    clock = fn ->
      send(test_pid, :clock_read)
      0
    end

    {:ok, _db} = RollupTSDB.start_link(clock: clock, cleanup_interval_ms: 10)

    assert_receive :clock_read, 1_000
    assert_receive :clock_read, 1_000
  end

  test "cleanup_interval_ms of :infinity arms no automatic cleanup at all" do
    test_pid = self()

    clock = fn ->
      send(test_pid, :clock_read)
      0
    end

    {:ok, _db} = RollupTSDB.start_link(clock: clock, cleanup_interval_ms: :infinity)

    refute_receive :clock_read, 300
  end

  test "bucket width defaults to one minute when the option is omitted" do
    {:ok, db} = RollupTSDB.start_link(clock: &Clock.now/0, cleanup_interval_ms: :infinity)

    :ok = RollupTSDB.insert(db, "m", %{}, 0, 1)
    :ok = RollupTSDB.insert(db, "m", %{}, 59_999, 2)
    :ok = RollupTSDB.insert(db, "m", %{}, 60_000, 3)

    [{_labels, buckets}] = RollupTSDB.query(db, "m", %{}, {0, 120_000})
    assert Enum.map(buckets, &elem(&1, 0)) == [0, 60_000]

    [{0, b0}, {60_000, b1}] = buckets
    assert b0.count == 2
    assert b1.count == 1
  end

  test "retention defaults to one hour when the option is omitted" do
    {:ok, db} =
      RollupTSDB.start_link(
        clock: &Clock.now/0,
        bucket_duration_ms: 1_000,
        cleanup_interval_ms: :infinity
      )

    # bucket 0 expires at now == 3_601_000; bucket 5000 not until 3_606_000
    :ok = RollupTSDB.insert(db, "m", %{}, 100, 1)
    :ok = RollupTSDB.insert(db, "m", %{}, 5_500, 2)

    Clock.set(3_600_999)
    :ok = sync_cleanup(db)
    [{_labels, before}] = RollupTSDB.query(db, "m", %{}, {0, 10_000})
    assert Enum.map(before, &elem(&1, 0)) == [0, 5_000]

    Clock.set(3_601_000)
    :ok = sync_cleanup(db)
    [{_labels, kept}] = RollupTSDB.query(db, "m", %{}, {0, 10_000})
    assert Enum.map(kept, &elem(&1, 0)) == [5_000]
  end

  # -------------------------------------------------------
  # Process registration
  # -------------------------------------------------------

  # Re-queries through the public API until `fun` reports success or the
  # deadline passes, so an automatically-armed timer can be observed without
  # waiting for any particular fixed duration.
  defp poll_until(budget_ms, fun) do
    deadline = System.monotonic_time(:millisecond) + budget_ms
    do_poll(deadline, fun)
  end

  defp do_poll(deadline, fun) do
    cond do
      fun.() -> true
      System.monotonic_time(:millisecond) >= deadline -> false
      true -> do_poll(deadline, fun)
    end
  end

  test "the :name option registers the process and the API works through that name" do
    name = :"rollup_tsdb_#{System.pid()}_#{System.unique_integer([:positive])}"

    {:ok, pid} =
      RollupTSDB.start_link(
        name: name,
        clock: &Clock.now/0,
        bucket_duration_ms: 1_000,
        retention_ms: 10_000,
        cleanup_interval_ms: :infinity
      )

    assert Process.whereis(name) == pid

    :ok = RollupTSDB.insert(name, "cpu", %{"host" => "a"}, 100, 7)
    [{%{"host" => "a"}, [{0, stats}]}] = RollupTSDB.query(name, "cpu", %{}, {0, 900})
    assert stats.count == 1
    assert stats.sum == 7
  end

  test "omitting :name starts the process unregistered but fully usable" do
    {:ok, pid} =
      RollupTSDB.start_link(
        clock: &Clock.now/0,
        bucket_duration_ms: 1_000,
        cleanup_interval_ms: :infinity
      )

    assert Process.info(pid, :registered_name) == {:registered_name, []}

    :ok = RollupTSDB.insert(pid, "m", %{}, 100, 1)
    [{_labels, [{0, stats}]}] = RollupTSDB.query(pid, "m", %{}, {0, 900})
    assert stats.count == 1
  end

  # -------------------------------------------------------
  # Unrecognized messages
  # -------------------------------------------------------

  test "an unrecognized info message is ignored and leaves stored data intact", %{db: db} do
    :ok = RollupTSDB.insert(db, "m", %{"host" => "a"}, 100, 7)

    send(db, :not_a_cleanup)
    send(db, {:unexpected, "payload"})
    send(db, [:stray, :list])

    # The query reply proves the stray messages were handled ahead of it
    # without the process dying.
    [{%{"host" => "a"}, [{0, stats}]}] = RollupTSDB.query(db, "m", %{}, {0, 900})
    assert stats.count == 1
    assert stats.sum == 7
    assert Process.alive?(db)

    :ok = RollupTSDB.insert(db, "m", %{"host" => "a"}, 200, 3)
    [{_labels, [{0, after_stats}]}] = RollupTSDB.query(db, "m", %{}, {0, 900})
    assert after_stats.count == 2
  end

  # -------------------------------------------------------
  # Automatic cleanup observed through the public API
  # -------------------------------------------------------

  test "an automatically armed timer expires buckets with no message from the test" do
    {:ok, db} =
      RollupTSDB.start_link(
        clock: &Clock.now/0,
        bucket_duration_ms: 1_000,
        retention_ms: 10_000,
        cleanup_interval_ms: 25
      )

    :ok = RollupTSDB.insert(db, "m", %{"host" => "a"}, 100, 1)
    [{_labels, [{0, _stats}]}] = RollupTSDB.query(db, "m", %{}, {0, 20_000})

    # Past the retention window for bucket 0, so the next automatic run drops it.
    Clock.set(100_000)

    assert poll_until(1_000, fn -> RollupTSDB.query(db, "m", %{}, {0, 200_000}) == [] end)
  end
end
