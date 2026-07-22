defmodule ShardedTSDB do
  @moduledoc """
  A time-series storage engine whose data is horizontally sharded across several
  worker processes.

  A single coordinator `GenServer` owns a fixed set of shard `GenServer`s. Each
  series — identified by `{metric_name, sorted_labels}` — lives on exactly one
  shard, determined by `:erlang.phash2/2`. Writes route to the owning shard;
  reads fan out across all shards and merge the results.

  Storage layout inside each shard (plain process state — no ETS):

      series_key => %{chunk_start => [{timestamp, value}, ...]}

  where `chunk_start = div(timestamp, chunk_duration_ms) * chunk_duration_ms` and
  the points within a chunk are kept sorted ascending by timestamp.

  Expired chunks are removed by a periodic cleanup pass driven by the coordinator
  (`Process.send_after/3` with the bare atom `:cleanup_tick`), and can also be run
  synchronously via `cleanup/1`.
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

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the coordinator process together with its shard workers.

  Options:

    * `:shards` — number of shard worker processes (default `#{@default_shards}`).
    * `:chunk_duration_ms` — chunk width in milliseconds (default `#{@default_chunk_duration_ms}`).
    * `:clock` — zero-arity function returning the current time in milliseconds.
    * `:retention_ms` — how long chunks are kept (default `#{@default_retention_ms}`).
    * `:cleanup_interval_ms` — cleanup period, or `:infinity` to disable.
    * `:name` — optional registration name for the coordinator.

  Returns `{:ok, coordinator_pid}`; the coordinator is the `server` argument
  expected by every other function in this module.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Inserts a single data point for the series `{metric_name, labels}`.

  The point is routed to the shard that owns the series. Always returns `:ok`.
  """
  @spec insert(GenServer.server(), any(), labels(), integer(), number()) :: :ok
  def insert(server, metric_name, labels, timestamp, value) do
    GenServer.call(server, {:insert, metric_name, labels, timestamp, value})
  end

  @doc """
  Queries raw points for every series matching `metric_name` and `label_matchers`.

  A series matches when its labels contain **all** key/value pairs in
  `label_matchers` (extra labels are allowed); `%{}` matches every series with the
  given metric name.

  Returns a list of `{labels, points}` tuples where `points` are the
  `{timestamp, value}` pairs with `start_ts <= timestamp <= end_ts`, sorted
  ascending. Series with no point in range are omitted. Series order is
  unspecified.
  """
  @spec query(GenServer.server(), any(), labels(), {integer(), integer()}) :: [series_result()]
  def query(server, metric_name, label_matchers, {start_ts, end_ts}) do
    GenServer.call(server, {:query, metric_name, label_matchers, {start_ts, end_ts}})
  end

  @doc """
  Queries matching series and aggregates their points into fixed-width windows.

  The range `[start_ts, end_ts)` is split into non-overlapping windows of
  `step_ms` milliseconds. For each series and window the points falling in
  `[window_start, window_start + step_ms)` are reduced with `aggregation`, one of
  `:sum`, `:avg` or `:max`. Empty windows are omitted, and a series whose windows
  are all empty is left out entirely.

  Returns a list of `{labels, agg_points}` tuples where `agg_points` is a list of
  `{window_start, value}` tuples sorted by window start.
  """
  @spec query_agg(
          GenServer.server(),
          any(),
          labels(),
          {integer(), integer()},
          aggregation(),
          pos_integer()
        ) :: [{labels(), [{integer(), number()}]}]
  def query_agg(server, metric_name, label_matchers, {start_ts, end_ts}, aggregation, step_ms)
      when aggregation in [:sum, :avg, :max] and is_integer(step_ms) and step_ms > 0 do
    series = query(server, metric_name, label_matchers, {start_ts, end_ts - 1})

    series
    |> Enum.map(fn {labels, points} ->
      {labels, aggregate(points, start_ts, end_ts, aggregation, step_ms)}
    end)
    |> Enum.reject(fn {_labels, agg_points} -> agg_points == [] end)
  end

  @doc """
  Returns the configured number of shard worker processes.
  """
  @spec shard_count(GenServer.server()) :: pos_integer()
  def shard_count(server) do
    GenServer.call(server, :shard_count)
  end

  @doc """
  Returns the 0-based index of the shard that owns `{metric_name, labels}`.
  """
  @spec shard_of(GenServer.server(), any(), labels()) :: non_neg_integer()
  def shard_of(server, metric_name, labels) do
    GenServer.call(server, {:shard_of, metric_name, labels})
  end

  @doc """
  Returns the total number of distinct series stored across all shards.
  """
  @spec series_count(GenServer.server()) :: non_neg_integer()
  def series_count(server) do
    GenServer.call(server, :series_count)
  end

  @doc """
  Runs a cleanup pass across all shards synchronously.

  Any chunk whose `chunk_start + chunk_duration_ms <= now - retention_ms` is
  dropped, and any series left without chunks is removed. Always returns `:ok`.
  """
  @spec cleanup(GenServer.server()) :: :ok
  def cleanup(server) do
    GenServer.call(server, :cleanup)
  end

  # ---------------------------------------------------------------------------
  # Coordinator callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    shard_count = Keyword.get(opts, :shards, @default_shards)
    chunk_duration_ms = Keyword.get(opts, :chunk_duration_ms, @default_chunk_duration_ms)
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    retention_ms = Keyword.get(opts, :retention_ms, @default_retention_ms)
    cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)

    Process.flag(:trap_exit, true)

    shards =
      for index <- 0..(shard_count - 1) do
        {:ok, pid} = ShardedTSDB.Shard.start_link(chunk_duration_ms: chunk_duration_ms)
        {index, pid}
      end
      |> Map.new()

    state = %{
      shards: shards,
      shard_count: shard_count,
      chunk_duration_ms: chunk_duration_ms,
      clock: clock,
      retention_ms: retention_ms,
      cleanup_interval_ms: cleanup_interval_ms
    }

    schedule_cleanup(state)
    {:ok, state}
  end

  @impl true
  def handle_call({:insert, metric_name, labels, timestamp, value}, _from, state) do
    key = series_key(metric_name, labels)
    pid = shard_pid(state, key)
    :ok = GenServer.call(pid, {:insert, key, labels, timestamp, value})
    {:reply, :ok, state}
  end

  def handle_call({:query, metric_name, label_matchers, range}, _from, state) do
    matchers = Map.to_list(label_matchers)

    results =
      state
      |> shard_pids()
      |> Enum.flat_map(fn pid ->
        GenServer.call(pid, {:query, metric_name, matchers, range})
      end)

    {:reply, results, state}
  end

  def handle_call(:shard_count, _from, state) do
    {:reply, state.shard_count, state}
  end

  def handle_call({:shard_of, metric_name, labels}, _from, state) do
    index = shard_index(series_key(metric_name, labels), state.shard_count)
    {:reply, index, state}
  end

  def handle_call(:series_count, _from, state) do
    total =
      state
      |> shard_pids()
      |> Enum.reduce(0, fn pid, acc -> acc + GenServer.call(pid, :series_count) end)

    {:reply, total, state}
  end

  def handle_call(:cleanup, _from, state) do
    run_cleanup(state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:cleanup_tick, state) do
    run_cleanup(state)
    schedule_cleanup(state)
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # Internal helpers (coordinator)
  # ---------------------------------------------------------------------------

  defp series_key(metric_name, labels) do
    {metric_name, Enum.sort(Map.to_list(labels))}
  end

  defp shard_index(key, shard_count) do
    :erlang.phash2(key, shard_count)
  end

  defp shard_pid(state, key) do
    Map.fetch!(state.shards, shard_index(key, state.shard_count))
  end

  defp shard_pids(state) do
    Enum.map(0..(state.shard_count - 1), &Map.fetch!(state.shards, &1))
  end

  defp run_cleanup(state) do
    cutoff = state.clock.() - state.retention_ms

    state
    |> shard_pids()
    |> Enum.each(fn pid -> :ok = GenServer.call(pid, {:cleanup, cutoff}) end)

    :ok
  end

  defp schedule_cleanup(%{cleanup_interval_ms: :infinity}), do: :ok

  defp schedule_cleanup(%{cleanup_interval_ms: interval}) when is_integer(interval) do
    Process.send_after(self(), :cleanup_tick, interval)
    :ok
  end

  defp schedule_cleanup(_state), do: :ok

  # ---------------------------------------------------------------------------
  # Aggregation
  # ---------------------------------------------------------------------------

  defp aggregate(points, start_ts, end_ts, aggregation, step_ms) do
    points
    |> Enum.filter(fn {ts, _v} -> ts >= start_ts and ts < end_ts end)
    |> Enum.group_by(fn {ts, _v} ->
      start_ts + div(ts - start_ts, step_ms) * step_ms
    end)
    |> Enum.map(fn {window_start, window_points} ->
      values = Enum.map(window_points, fn {_ts, v} -> v end)
      {window_start, apply_agg(aggregation, values)}
    end)
    |> Enum.sort_by(fn {window_start, _v} -> window_start end)
  end

  defp apply_agg(:sum, values), do: Enum.sum(values)
  defp apply_agg(:max, values), do: Enum.max(values)
  defp apply_agg(:avg, values), do: Enum.sum(values) / length(values)

  # ---------------------------------------------------------------------------
  # Shard worker
  # ---------------------------------------------------------------------------

  defmodule Shard do
    @moduledoc """
    A single shard worker for `ShardedTSDB`.

    Holds the series it owns entirely in its own `GenServer` state:

        %{series_key => %{labels: labels, chunks: %{chunk_start => [point]}}}

    Shards are started and driven exclusively by the `ShardedTSDB` coordinator.
    """

    use GenServer

    @doc """
    Starts a shard worker. Requires `:chunk_duration_ms` in `opts`.
    """
    @spec start_link(keyword()) :: GenServer.on_start()
    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts)
    end

    @impl true
    def init(opts) do
      {:ok,
       %{
         chunk_duration_ms: Keyword.fetch!(opts, :chunk_duration_ms),
         series: %{}
       }}
    end

    @impl true
    def handle_call({:insert, key, labels, timestamp, value}, _from, state) do
      chunk_start = div(timestamp, state.chunk_duration_ms) * state.chunk_duration_ms

      entry = Map.get(state.series, key, %{labels: labels, chunks: %{}})
      chunk = Map.get(entry.chunks, chunk_start, [])
      new_chunk = insert_sorted(chunk, {timestamp, value})
      new_entry = %{entry | chunks: Map.put(entry.chunks, chunk_start, new_chunk)}

      {:reply, :ok, %{state | series: Map.put(state.series, key, new_entry)}}
    end

    def handle_call({:query, metric_name, matchers, {start_ts, end_ts}}, _from, state) do
      results =
        state.series
        |> Enum.filter(fn {{name, _sorted}, entry} ->
          name == metric_name and matches?(entry.labels, matchers)
        end)
        |> Enum.map(fn {_key, entry} -> {entry.labels, points_in_range(entry, start_ts, end_ts)} end)
        |> Enum.reject(fn {_labels, points} -> points == [] end)

      {:reply, results, state}
    end

    def handle_call(:series_count, _from, state) do
      {:reply, map_size(state.series), state}
    end

    def handle_call({:cleanup, cutoff}, _from, state) do
      duration = state.chunk_duration_ms

      series =
        state.series
        |> Enum.reduce(%{}, fn {key, entry}, acc ->
          chunks =
            entry.chunks
            |> Enum.reject(fn {chunk_start, _points} -> chunk_start + duration <= cutoff end)
            |> Map.new()

          if map_size(chunks) == 0 do
            acc
          else
            Map.put(acc, key, %{entry | chunks: chunks})
          end
        end)

      {:reply, :ok, %{state | series: series}}
    end

    defp insert_sorted(points, {timestamp, _value} = point) do
      {before, rest} = Enum.split_while(points, fn {ts, _v} -> ts <= timestamp end)
      before ++ [point | rest]
    end

    defp matches?(labels, matchers) do
      Enum.all?(matchers, fn {k, v} -> Map.get(labels, k) == v end)
    end

    defp points_in_range(entry, start_ts, end_ts) do
      entry.chunks
      |> Enum.flat_map(fn {_chunk_start, points} -> points end)
      |> Enum.filter(fn {ts, _v} -> ts >= start_ts and ts <= end_ts end)
      |> Enum.sort_by(fn {ts, _v} -> ts end)
    end
  end
end