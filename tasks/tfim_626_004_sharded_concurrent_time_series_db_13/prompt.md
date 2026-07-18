# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule ShardedTSDB do
  @moduledoc """
  A horizontally sharded time-series storage engine.

  Starting the engine (`start_link/1`) spins up one coordinator `GenServer`
  that owns a fixed set of shard `GenServer` workers. Each series lives on
  exactly one shard, chosen by hashing its identity. Writes route to the
  owning shard; reads fan out across every shard and are merged by the
  coordinator.

  A series is identified by `{metric_name, sorted_labels}` where
  `sorted_labels = Enum.sort(Map.to_list(labels))`, so label ordering never
  produces duplicate series. The owning shard index is
  `:erlang.phash2({metric_name, sorted_labels}, shard_count)`.

  All storage lives in the shard processes' `GenServer` state (no ETS). Each
  shard keeps a map of `series_key => %{chunk_start => sorted_points}` where
  `chunk_start = div(timestamp, chunk_duration_ms) * chunk_duration_ms` and
  points within a chunk are sorted ascending by timestamp.
  """

  use GenServer

  @type server :: GenServer.server()
  @type labels :: %{optional(term()) => term()}
  @type point :: {integer(), number()}
  @type series_result :: {labels(), [point()]}

  # ── Public API ────────────────────────────────────────────────────────

  @doc """
  Starts the coordinator and its shard workers.

  Options:

    * `:shards` — number of shard workers (default `4`).
    * `:chunk_duration_ms` — chunk width in ms (default `60_000`).
    * `:clock` — zero-arity fn returning current time in ms
      (default `fn -> System.monotonic_time(:millisecond) end`).
    * `:name` — optional registration name for the coordinator.
    * `:retention_ms` — how long to keep chunks (default `3_600_000`).
    * `:cleanup_interval_ms` — periodic cleanup interval, or `:infinity`
      to disable (default `60_000`).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Inserts a single `{timestamp, value}` point into the series identified by
  `metric_name` and `labels`, routing it to the owning shard.
  """
  @spec insert(server(), term(), labels(), integer(), number()) :: :ok
  def insert(server, metric_name, labels, timestamp, value) do
    GenServer.call(server, {:insert, metric_name, labels, timestamp, value})
  end

  @doc """
  Fans out across all shards and returns the matching series.

  `label_matchers` is a map; a series matches when it contains all of the
  given key-value pairs (it may contain more). `%{}` matches every series
  with the metric name. Each result is `{labels, points}` where `points` is
  the list of `{timestamp, value}` in `start_ts..end_ts` inclusive, sorted
  ascending. Series with no in-range point are omitted.
  """
  @spec query(server(), term(), labels(), {integer(), integer()}) ::
          [series_result()]
  def query(server, metric_name, label_matchers, {start_ts, end_ts}) do
    GenServer.call(server, {:query, metric_name, label_matchers, {start_ts, end_ts}})
  end

  @doc """
  Like `query/4`, but aggregates each matched series into fixed windows.

  The range `[start_ts, end_ts)` is split into non-overlapping windows of
  width `step_ms`. For each window, the points whose timestamps fall in
  `[window_start, window_start + step_ms)` are reduced with `aggregation`
  (`:sum`, `:avg` or `:max`); empty windows are omitted. Each result is
  `{labels, agg_points}` with `agg_points` a list of
  `{window_start, aggregated_value}` sorted by window start. Series whose
  windows are all empty are dropped.
  """
  @spec query_agg(
          server(),
          term(),
          labels(),
          {integer(), integer()},
          :sum | :avg | :max,
          pos_integer()
        ) :: [series_result()]
  def query_agg(server, metric_name, label_matchers, {start_ts, end_ts}, aggregation, step_ms) do
    msg = {:query_agg, metric_name, label_matchers, {start_ts, end_ts}, aggregation, step_ms}
    GenServer.call(server, msg)
  end

  @doc """
  Returns the configured number of shards.
  """
  @spec shard_count(server()) :: non_neg_integer()
  def shard_count(server) do
    GenServer.call(server, :shard_count)
  end

  @doc """
  Returns the 0-based shard index that owns the given series.
  """
  @spec shard_of(server(), term(), labels()) :: non_neg_integer()
  def shard_of(server, metric_name, labels) do
    GenServer.call(server, {:shard_of, metric_name, labels})
  end

  @doc """
  Returns the total number of distinct series stored across all shards.
  """
  @spec series_count(server()) :: non_neg_integer()
  def series_count(server) do
    GenServer.call(server, :series_count)
  end

  @doc """
  Synchronously runs cleanup across all shards and returns `:ok`.

  Removes any chunk whose `chunk_start + chunk_duration_ms` is less than or
  equal to `now - retention_ms` (with `now` from `:clock`) and drops any
  series left with zero chunks.
  """
  @spec cleanup(server()) :: :ok
  def cleanup(server) do
    GenServer.call(server, :cleanup)
  end

  # ── Coordinator callbacks ─────────────────────────────────────────────

  @impl true
  def init(opts) do
    count = Keyword.get(opts, :shards, 4)
    chunk = Keyword.get(opts, :chunk_duration_ms, 60_000)
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    retention = Keyword.get(opts, :retention_ms, 3_600_000)
    interval = Keyword.get(opts, :cleanup_interval_ms, 60_000)

    shards =
      for _ <- 1..count do
        {:ok, pid} = ShardedTSDB.Shard.start_link(chunk)
        pid
      end

    state = %{
      shards: List.to_tuple(shards),
      shard_count: count,
      chunk_duration_ms: chunk,
      clock: clock,
      retention_ms: retention,
      cleanup_interval_ms: interval
    }

    schedule_cleanup(state)
    {:ok, state}
  end

  @impl true
  def handle_call({:insert, metric, labels, ts, value}, _from, state) do
    key = series_key(metric, labels)
    idx = :erlang.phash2(key, state.shard_count)
    pid = elem(state.shards, idx)
    :ok = GenServer.call(pid, {:insert, key, ts, value})
    {:reply, :ok, state}
  end

  def handle_call({:query, metric, matchers, range}, _from, state) do
    results =
      state.shards
      |> Tuple.to_list()
      |> Enum.flat_map(fn pid -> GenServer.call(pid, {:query, metric, matchers, range}) end)

    {:reply, results, state}
  end

  def handle_call({:query_agg, metric, matchers, range, agg, step}, _from, state) do
    msg = {:query_agg, metric, matchers, range, agg, step}

    results =
      state.shards
      |> Tuple.to_list()
      |> Enum.flat_map(fn pid -> GenServer.call(pid, msg) end)

    {:reply, results, state}
  end

  def handle_call(:shard_count, _from, state) do
    {:reply, state.shard_count, state}
  end

  def handle_call({:shard_of, metric, labels}, _from, state) do
    idx = :erlang.phash2(series_key(metric, labels), state.shard_count)
    {:reply, idx, state}
  end

  def handle_call(:series_count, _from, state) do
    total =
      state.shards
      |> Tuple.to_list()
      |> Enum.reduce(0, fn pid, acc -> acc + GenServer.call(pid, :series_count) end)

    {:reply, total, state}
  end

  def handle_call(:cleanup, _from, state) do
    do_cleanup(state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:cleanup_tick, state) do
    do_cleanup(state)
    schedule_cleanup(state)
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ── Coordinator helpers ───────────────────────────────────────────────

  defp series_key(metric, labels) do
    {metric, Enum.sort(Map.to_list(labels))}
  end

  defp schedule_cleanup(%{cleanup_interval_ms: :infinity}), do: :ok

  defp schedule_cleanup(%{cleanup_interval_ms: interval}) do
    Process.send_after(self(), :cleanup_tick, interval)
    :ok
  end

  defp do_cleanup(state) do
    cutoff = state.clock.() - state.retention_ms

    state.shards
    |> Tuple.to_list()
    |> Enum.each(fn pid -> GenServer.call(pid, {:cleanup, cutoff}) end)

    :ok
  end
end

defmodule ShardedTSDB.Shard do
  @moduledoc false

  use GenServer

  @spec start_link(pos_integer()) :: GenServer.on_start()
  def start_link(chunk_duration_ms) do
    GenServer.start_link(__MODULE__, chunk_duration_ms)
  end

  @impl true
  def init(chunk_duration_ms) do
    {:ok, %{chunk_duration_ms: chunk_duration_ms, data: %{}}}
  end

  @impl true
  def handle_call({:insert, key, ts, value}, _from, state) do
    chunk_start = div(ts, state.chunk_duration_ms) * state.chunk_duration_ms
    series = Map.get(state.data, key, %{})
    chunk = Map.get(series, chunk_start, [])
    new_chunk = Enum.sort_by([{ts, value} | chunk], fn {t, _} -> t end)
    new_series = Map.put(series, chunk_start, new_chunk)
    new_data = Map.put(state.data, key, new_series)
    {:reply, :ok, %{state | data: new_data}}
  end

  def handle_call({:query, metric, matchers, {start_ts, end_ts}}, _from, state) do
    results =
      for {{m, sorted_labels} = _key, chunks} <- state.data,
          m == metric,
          label_match?(sorted_labels, matchers),
          points = in_range_points(chunks, start_ts, end_ts),
          points != [],
          do: {Map.new(sorted_labels), points}

    {:reply, results, state}
  end

  def handle_call({:query_agg, metric, matchers, range, agg, step}, _from, state) do
    {start_ts, end_ts} = range

    results =
      for {{m, sorted_labels}, chunks} <- state.data,
          m == metric,
          label_match?(sorted_labels, matchers),
          agg_points = aggregate(chunks, start_ts, end_ts, step, agg),
          agg_points != [],
          do: {Map.new(sorted_labels), agg_points}

    {:reply, results, state}
  end

  def handle_call(:series_count, _from, state) do
    {:reply, map_size(state.data), state}
  end

  def handle_call({:cleanup, cutoff}, _from, state) do
    new_data =
      Enum.reduce(state.data, %{}, fn {key, chunks}, acc ->
        kept =
          for {cs, pts} <- chunks,
              cs + state.chunk_duration_ms > cutoff,
              into: %{},
              do: {cs, pts}

        if map_size(kept) == 0, do: acc, else: Map.put(acc, key, kept)
      end)

    {:reply, :ok, %{state | data: new_data}}
  end

  # ── Shard helpers ─────────────────────────────────────────────────────

  defp label_match?(sorted_labels, matchers) do
    lmap = Map.new(sorted_labels)
    Enum.all?(matchers, fn {k, v} -> Map.fetch(lmap, k) == {:ok, v} end)
  end

  defp in_range_points(chunks, start_ts, end_ts) do
    chunks
    |> Map.values()
    |> Enum.concat()
    |> Enum.filter(fn {ts, _} -> ts >= start_ts and ts <= end_ts end)
    |> Enum.sort_by(fn {ts, _} -> ts end)
  end

  defp aggregate(chunks, start_ts, end_ts, step, agg) do
    chunks
    |> Map.values()
    |> Enum.concat()
    |> Enum.filter(fn {ts, _} -> ts >= start_ts and ts < end_ts end)
    |> Enum.group_by(
      fn {ts, _} -> start_ts + div(ts - start_ts, step) * step end,
      fn {_, v} -> v end
    )
    |> Enum.map(fn {window_start, vals} -> {window_start, apply_agg(agg, vals)} end)
    |> Enum.sort_by(fn {window_start, _} -> window_start end)
  end

  defp apply_agg(:sum, vals), do: Enum.sum(vals)
  defp apply_agg(:avg, vals), do: Enum.sum(vals) / length(vals)
  defp apply_agg(:max, vals), do: Enum.max(vals)
end
```

## Test harness — implement the `# TODO` test

```elixir
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
    # TODO
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

  test "default chunk_duration_ms of 60_000 governs the cleanup boundary" do
    {:ok, db} =
      ShardedTSDB.start_link(
        shards: 2,
        clock: &Clock.now/0,
        retention_ms: 10_000,
        cleanup_interval_ms: :infinity
      )

    :ok = ShardedTSDB.insert(db, "m", %{}, 0, 1)
    :ok = ShardedTSDB.insert(db, "m", %{}, 60_000, 2)

    # cutoff = 60_000. With the default 60_000 chunk width the chunk starting at 0
    # ends exactly at the cutoff and is dropped; the chunk at 60_000 survives.
    Clock.set(70_000)
    assert :ok = ShardedTSDB.cleanup(db)

    [{_labels, points}] = ShardedTSDB.query(db, "m", %{}, {0, 200_000})
    assert points == [{60_000, 2}]
  end

  test "default retention_ms keeps chunks until an hour of clock time has passed" do
    {:ok, db} =
      ShardedTSDB.start_link(
        shards: 2,
        clock: &Clock.now/0,
        chunk_duration_ms: 1_000,
        cleanup_interval_ms: :infinity
      )

    :ok = ShardedTSDB.insert(db, "m", %{}, 0, 1)

    # cutoff = 0; the chunk ending at 1_000 is still within the default retention.
    Clock.set(3_600_000)
    assert :ok = ShardedTSDB.cleanup(db)
    assert [{_labels, [{0, 1}]}] = ShardedTSDB.query(db, "m", %{}, {0, 10_000})

    # cutoff = 1_000; the chunk ending at 1_000 now expires.
    Clock.set(3_601_000)
    assert :ok = ShardedTSDB.cleanup(db)
    assert [] = ShardedTSDB.query(db, "m", %{}, {0, 10_000})
    assert ShardedTSDB.series_count(db) == 0
  end

  test "a single :cleanup_tick performs exactly one cleanup pass" do
    test_pid = self()

    clock = fn ->
      send(test_pid, :clock_read)
      0
    end

    {:ok, db} =
      ShardedTSDB.start_link(
        shards: 2,
        clock: clock,
        chunk_duration_ms: 1_000,
        retention_ms: 10_000,
        cleanup_interval_ms: :infinity
      )

    :ok = ShardedTSDB.insert(db, "m", %{}, 100, 1)
    send(db, :cleanup_tick)

    # A cleanup pass reads the clock exactly once; a second pass would read again.
    assert_receive :clock_read, 500
    refute_receive :clock_read, 300
    assert ShardedTSDB.series_count(db) == 1
  end

  test "a matcher pair whose key is absent from the series does not match", %{db: db} do
    :ok = ShardedTSDB.insert(db, "cpu", %{"region" => "eu"}, 100, 1)
    :ok = ShardedTSDB.insert(db, "cpu", %{"host" => nil}, 100, 2)

    # Only the series that actually contains the pair {"host", nil} may match.
    result = ShardedTSDB.query(db, "cpu", %{"host" => nil}, {0, 200})
    assert result == [{%{"host" => nil}, [{100, 2}]}]
  end

  test "cleanup_interval_ms of :infinity arms no periodic cleanup timer" do
    test_pid = self()

    clock = fn ->
      send(test_pid, :clock_read)
      0
    end

    {:ok, db} =
      ShardedTSDB.start_link(
        shards: 2,
        clock: clock,
        chunk_duration_ms: 1_000,
        retention_ms: 10_000,
        cleanup_interval_ms: :infinity
      )

    :ok = ShardedTSDB.insert(db, "m", %{}, 100, 1)

    # No cleanup pass may ever run on its own, so the clock is never read.
    refute_receive :clock_read, 300
    assert ShardedTSDB.series_count(db) == 1
  end

  test "query_agg windows begin at start_ts even when it is not step aligned", %{db: db} do
    for {ts, v} <- [{150, 1}, {400, 2}, {450, 4}, {700, 8}] do
      :ok = ShardedTSDB.insert(db, "m", %{}, ts, v)
    end

    [{_labels, agg}] = ShardedTSDB.query_agg(db, "m", %{}, {150, 750}, :sum, 300)
    assert agg == [{150, 3}, {450, 12}]
  end
end
```
