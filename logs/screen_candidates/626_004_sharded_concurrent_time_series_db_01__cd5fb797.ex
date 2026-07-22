defmodule ShardedTSDB do
  @moduledoc """
  A time-series storage engine whose data is horizontally sharded across several
  worker processes.

  A single coordinator `GenServer` owns a fixed set of shard `GenServer`s. Each series
  lives on exactly one shard, writes route to the owning shard, and reads fan out
  across all shards and merge.

  ## Series identity

  A series is identified by `{metric_name, sorted_labels}` where
  `sorted_labels = Enum.sort(Map.to_list(labels))`, so label ordering never creates
  duplicate series.

  ## Routing

  The shard index that owns a series is
  `:erlang.phash2({metric_name, sorted_labels}, shard_count)` — a 0-based integer in
  `0..(shard_count - 1)`.

  ## Storage layout

  Each shard keeps its own series independently as
  `series_key => %{chunk_start => sorted_points}` where
  `chunk_start = div(timestamp, chunk_duration_ms) * chunk_duration_ms` and points
  within a chunk are kept sorted ascending by timestamp. All storage lives in the
  shard processes' `GenServer` state — no ETS is used.

  ## Retention

  The coordinator periodically triggers cleanup across every shard using
  `Process.send_after/3`. Cleanup removes any chunk whose
  `chunk_start + chunk_duration_ms` is less than or equal to `now - retention_ms`,
  and drops any series left with zero chunks.
  """

  use GenServer

  @default_shards 4
  @default_chunk_duration_ms 60_000
  @default_retention_ms 3_600_000
  @default_cleanup_interval_ms 60_000

  @type labels :: %{optional(any()) => any()}
  @type point :: {integer(), number()}
  @type series_result :: {labels(), [point()]}
  @type aggregation :: :sum | :avg | :max

  defmodule Shard do
    @moduledoc """
    A single shard worker process. Owns the subset of series routed to it and holds
    all of their chunks in its `GenServer` state.
    """

    use GenServer

    @doc """
    Starts a shard worker.

    Options: `:chunk_duration_ms`, `:retention_ms` and `:clock`.
    """
    @spec start_link(keyword()) :: GenServer.on_start()
    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts)
    end

    @impl true
    def init(opts) do
      state = %{
        chunk_duration_ms: Keyword.fetch!(opts, :chunk_duration_ms),
        retention_ms: Keyword.fetch!(opts, :retention_ms),
        clock: Keyword.fetch!(opts, :clock),
        series: %{}
      }

      {:ok, state}
    end

    @impl true
    def handle_cast({:insert, key, timestamp, value}, state) do
      chunk_start = div(timestamp, state.chunk_duration_ms) * state.chunk_duration_ms

      chunks = Map.get(state.series, key, %{})
      points = Map.get(chunks, chunk_start, [])
      points = insert_sorted(points, {timestamp, value})

      chunks = Map.put(chunks, chunk_start, points)
      {:noreply, %{state | series: Map.put(state.series, key, chunks)}}
    end

    @impl true
    def handle_call({:query, metric_name, matchers, start_ts, end_ts}, _from, state) do
      results =
        state.series
        |> Enum.filter(fn {{name, sorted_labels}, _chunks} ->
          name == metric_name and matches?(sorted_labels, matchers)
        end)
        |> Enum.flat_map(fn {{_name, sorted_labels}, chunks} ->
          points = points_in_range(chunks, start_ts, end_ts)

          case points do
            [] -> []
            _ -> [{Map.new(sorted_labels), points}]
          end
        end)

      {:reply, results, state}
    end

    def handle_call({:series_count}, _from, state) do
      {:reply, map_size(state.series), state}
    end

    def handle_call({:cleanup}, _from, state) do
      {:reply, :ok, do_cleanup(state)}
    end

    @impl true
    def handle_info({:cleanup}, state) do
      {:noreply, do_cleanup(state)}
    end

    def handle_info(_msg, state), do: {:noreply, state}

    # Inserts a point keeping the chunk sorted ascending by timestamp.
    defp insert_sorted([], point), do: [point]

    defp insert_sorted([{ts, _v} = head | tail] = points, {new_ts, _} = point) do
      if new_ts < ts do
        [point | points]
      else
        [head | insert_sorted(tail, point)]
      end
    end

    # A series matches when its labels contain every key/value pair in `matchers`.
    defp matches?(sorted_labels, matchers) do
      label_map = Map.new(sorted_labels)

      Enum.all?(matchers, fn {k, v} -> Map.get(label_map, k) == v end)
    end

    defp points_in_range(chunks, start_ts, end_ts) do
      chunks
      |> Enum.sort_by(fn {chunk_start, _points} -> chunk_start end)
      |> Enum.flat_map(fn {_chunk_start, points} -> points end)
      |> Enum.filter(fn {ts, _v} -> ts >= start_ts and ts <= end_ts end)
      |> Enum.sort_by(fn {ts, _v} -> ts end)
    end

    defp do_cleanup(state) do
      now = state.clock.()
      cutoff = now - state.retention_ms

      series =
        state.series
        |> Enum.reduce(%{}, fn {key, chunks}, acc ->
          kept =
            chunks
            |> Enum.reject(fn {chunk_start, _points} ->
              chunk_start + state.chunk_duration_ms <= cutoff
            end)
            |> Map.new()

          if map_size(kept) == 0, do: acc, else: Map.put(acc, key, kept)
        end)

      %{state | series: series}
    end
  end

  # ----------------------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------------------

  @doc """
  Starts the coordinator together with `:shards` independent shard worker processes.

  ## Options

    * `:shards` — number of shard worker processes (default `#{@default_shards}`).
    * `:chunk_duration_ms` — chunk width in milliseconds
      (default `#{@default_chunk_duration_ms}`).
    * `:clock` — zero-arity function returning the current time in milliseconds
      (default `fn -> System.monotonic_time(:millisecond) end`).
    * `:name` — optional registration name for the coordinator.
    * `:retention_ms` — how long to keep chunks (default `#{@default_retention_ms}`).
    * `:cleanup_interval_ms` — how often cleanup runs across all shards
      (default `#{@default_cleanup_interval_ms}`); `:infinity` disables it.

  Returns the coordinator process, which is the `server` argument of every other
  public function.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Inserts `value` at `timestamp` for the series `{metric_name, labels}`.

  The point is routed to the shard that owns the series. Always returns `:ok`.
  """
  @spec insert(GenServer.server(), any(), labels(), integer(), number()) :: :ok
  def insert(server, metric_name, labels, timestamp, value) do
    GenServer.call(server, {:insert, metric_name, labels, timestamp, value})
  end

  @doc """
  Queries raw points across all shards and merges the results.

  A series matches when its labels contain all key/value pairs in `label_matchers`
  (it may have more); `%{}` matches every series with that metric name.

  Returns a list of `{labels, points}` tuples where `points` are the `{timestamp, value}`
  pairs sorted ascending and filtered to `start_ts <= timestamp <= end_ts`. Series with
  no point in range are omitted. The order of series in the merged list is unspecified.
  """
  @spec query(GenServer.server(), any(), labels(), {integer(), integer()}) :: [series_result()]
  def query(server, metric_name, label_matchers, {start_ts, end_ts}) do
    GenServer.call(server, {:query, metric_name, label_matchers, start_ts, end_ts})
  end

  @doc """
  Queries points across all shards and aggregates them into fixed-width windows.

  The range `[start_ts, end_ts)` is divided into non-overlapping windows of `step_ms`
  milliseconds starting at `start_ts`. For each matched series and each window, the
  points whose timestamps fall in `[window_start, window_start + step_ms)` are reduced
  with `aggregation`, one of `:sum`, `:avg` or `:max`. Windows with no points are
  omitted, and a series whose windows are all omitted is left out of the result.

  Returns a list of `{labels, agg_points}` tuples where `agg_points` is a list of
  `{window_start, aggregated_value}` tuples sorted by window start.
  """
  @spec query_agg(
          GenServer.server(),
          any(),
          labels(),
          {integer(), integer()},
          aggregation(),
          pos_integer()
        ) :: [{labels(), [{integer(), number()}]}]
  def query_agg(server, metric_name, label_matchers, {start_ts, end_ts}, aggregation, step_ms) do
    server
    |> query(metric_name, label_matchers, {start_ts, end_ts - 1})
    |> Enum.flat_map(fn {labels, points} ->
      case aggregate(points, start_ts, end_ts, aggregation, step_ms) do
        [] -> []
        agg_points -> [{labels, agg_points}]
      end
    end)
  end

  @doc """
  Returns the configured number of shard worker processes.
  """
  @spec shard_count(GenServer.server()) :: pos_integer()
  def shard_count(server) do
    GenServer.call(server, :shard_count)
  end

  @doc """
  Returns the 0-based shard index that owns the series `{metric_name, labels}`.
  """
  @spec shard_of(GenServer.server(), any(), labels()) :: non_neg_integer()
  def shard_of(server, metric_name, labels) do
    :erlang.phash2(series_key(metric_name, labels), shard_count(server))
  end

  @doc """
  Returns the total number of distinct series stored across all shards.
  """
  @spec series_count(GenServer.server()) :: non_neg_integer()
  def series_count(server) do
    GenServer.call(server, :series_count)
  end

  @doc """
  Synchronously runs retention cleanup across all shards.

  Removes every chunk whose `chunk_start + chunk_duration_ms` is less than or equal to
  `now - retention_ms` (with `now` taken from `:clock`), and drops any series left with
  zero chunks. Always returns `:ok`.
  """
  @spec cleanup(GenServer.server()) :: :ok
  def cleanup(server) do
    GenServer.call(server, :cleanup)
  end

  # ----------------------------------------------------------------------------
  # Coordinator callbacks
  # ----------------------------------------------------------------------------

  @impl true
  def init(opts) do
    shard_count = Keyword.get(opts, :shards, @default_shards)
    chunk_duration_ms = Keyword.get(opts, :chunk_duration_ms, @default_chunk_duration_ms)
    retention_ms = Keyword.get(opts, :retention_ms, @default_retention_ms)
    cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)

    shard_opts = [
      chunk_duration_ms: chunk_duration_ms,
      retention_ms: retention_ms,
      clock: clock
    ]

    shards =
      Enum.map(0..(shard_count - 1)//1, fn _index ->
        {:ok, pid} = Shard.start_link(shard_opts)
        pid
      end)

    state = %{
      shards: shards,
      shard_count: shard_count,
      chunk_duration_ms: chunk_duration_ms,
      retention_ms: retention_ms,
      cleanup_interval_ms: cleanup_interval_ms,
      clock: clock
    }

    schedule_cleanup(cleanup_interval_ms)
    {:ok, state}
  end

  @impl true
  def handle_call({:insert, metric_name, labels, timestamp, value}, _from, state) do
    key = series_key(metric_name, labels)
    index = :erlang.phash2(key, state.shard_count)
    pid = Enum.at(state.shards, index)

    GenServer.cast(pid, {:insert, key, timestamp, value})
    {:reply, :ok, state}
  end

  def handle_call({:query, metric_name, matchers, start_ts, end_ts}, _from, state) do
    results =
      state.shards
      |> Enum.flat_map(fn pid ->
        GenServer.call(pid, {:query, metric_name, matchers, start_ts, end_ts})
      end)

    {:reply, results, state}
  end

  def handle_call(:shard_count, _from, state) do
    {:reply, state.shard_count, state}
  end

  def handle_call(:series_count, _from, state) do
    total =
      state.shards
      |> Enum.map(fn pid -> GenServer.call(pid, {:series_count}) end)
      |> Enum.sum()

    {:reply, total, state}
  end

  def handle_call(:cleanup, _from, state) do
    Enum.each(state.shards, fn pid -> GenServer.call(pid, {:cleanup}) end)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    Enum.each(state.shards, fn pid -> send(pid, {:cleanup}) end)
    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ----------------------------------------------------------------------------
  # Internals
  # ----------------------------------------------------------------------------

  defp schedule_cleanup(:infinity), do: :ok

  defp schedule_cleanup(interval) when is_integer(interval) and interval > 0 do
    Process.send_after(self(), :cleanup, interval)
    :ok
  end

  defp schedule_cleanup(_other), do: :ok

  defp series_key(metric_name, labels) do
    {metric_name, Enum.sort(Map.to_list(labels))}
  end

  # Buckets `points` into `[start_ts, end_ts)` windows of `step_ms` and reduces each
  # non-empty window with `aggregation`.
  defp aggregate(points, start_ts, end_ts, aggregation, step_ms) do
    buckets =
      Enum.reduce(points, %{}, fn {ts, value}, acc ->
        if ts >= start_ts and ts < end_ts do
          window_start = start_ts + div(ts - start_ts, step_ms) * step_ms
          Map.update(acc, window_start, [value], fn values -> [value | values] end)
        else
          acc
        end
      end)

    buckets
    |> Enum.map(fn {window_start, values} ->
      {window_start, apply_agg(aggregation, values)}
    end)
    |> Enum.sort_by(fn {window_start, _value} -> window_start end)
  end

  defp apply_agg(:sum, values), do: Enum.sum(values)
  defp apply_agg(:max, values), do: Enum.max(values)
  defp apply_agg(:avg, values), do: Enum.sum(values) / length(values)
end