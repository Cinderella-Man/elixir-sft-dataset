Implement the private `aggregate/5` function in the `ShardedTSDB.Shard` module.
It takes `(chunks, start_ts, end_ts, step, agg)` — where `chunks` is a series'
`%{chunk_start => sorted_points}` map — and computes the windowed aggregation for
that one series.

Gather every `{timestamp, value}` point across all of the series' chunks and keep
only those whose timestamp falls in the half-open range `[start_ts, end_ts)`. Assign
each surviving point to its window by computing the window start as
`start_ts + div(ts - start_ts, step) * step`, so the range is split into
non-overlapping windows `[start_ts, start_ts + step)`, `[start_ts + step, start_ts + 2*step)`,
and so on. Group the points' values by window start, reduce each window's values with
the requested aggregation via `apply_agg/2` (`:sum`, `:avg` or `:max`), and produce a
list of `{window_start, aggregated_value}` tuples sorted ascending by window start.
Windows with no points must simply not appear (they contribute nothing to the list),
and the result is `[]` when no point falls in range.

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
    Enum.all?(matchers, fn {k, v} -> Map.get(lmap, k) == v end)
  end

  defp in_range_points(chunks, start_ts, end_ts) do
    chunks
    |> Map.values()
    |> Enum.concat()
    |> Enum.filter(fn {ts, _} -> ts >= start_ts and ts <= end_ts end)
    |> Enum.sort_by(fn {ts, _} -> ts end)
  end

  defp aggregate(chunks, start_ts, end_ts, step, agg) do
    # TODO
  end

  defp apply_agg(:sum, vals), do: Enum.sum(vals)
  defp apply_agg(:avg, vals), do: Enum.sum(vals) / length(vals)
  defp apply_agg(:max, vals), do: Enum.max(vals)
end
```