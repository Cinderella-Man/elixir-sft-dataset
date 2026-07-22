defmodule TSDB do
  @moduledoc """
  An in-memory, chunked time-series storage engine implemented as a `GenServer`.

  Metrics are identified by a metric name plus an exact set of labels. Every
  unique series (metric name + label set) is stored as a collection of
  time-based chunks. Each chunk covers a window of `chunk_duration_ms`
  milliseconds and holds the series' data points, kept sorted by timestamp.

  Internally the storage is a nested map keyed by the "series key"
  `{metric_name, sorted_labels}`, where `sorted_labels` is the label map turned
  into a sorted key/value list so that label ordering can never produce
  duplicate series. Each series key maps to a `chunk_start => [points]` map.

  The engine supports raw range queries (`query/4`), windowed aggregation
  (`query_agg/6`), and periodic retention-based cleanup of expired chunks.

  All state lives inside the process; there is no ETS and there are no helper
  processes. Only OTP standard library modules are used.
  """

  use GenServer

  @default_chunk_duration_ms 60_000
  @default_retention_ms 3_600_000
  @default_cleanup_interval_ms 60_000

  @typedoc "A single stored data point: `{timestamp_ms, value}`."
  @type point :: {integer(), number()}

  @typedoc "A result row: the full label map and its list of points."
  @type row :: {map(), [point()]}

  @doc """
  Starts the `TSDB` process.

  Options:

    * `:chunk_duration_ms` - width of each storage chunk in milliseconds
      (default `#{@default_chunk_duration_ms}`).
    * `:clock` - zero-arity function returning the current time in
      milliseconds (default `System.monotonic_time(:millisecond)`).
    * `:name` - optional process registration name.
    * `:retention_ms` - how long chunks are kept before cleanup
      (default `#{@default_retention_ms}`).
    * `:cleanup_interval_ms` - how often automatic cleanup runs, or
      `:infinity` to disable (default `#{@default_cleanup_interval_ms}`).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Inserts a single data point for the given metric and label set.

  The point is routed to the chunk determined by `timestamp` and the configured
  `chunk_duration_ms`, and stored in timestamp order within that chunk. Always
  returns `:ok`.
  """
  @spec insert(GenServer.server(), String.t(), map(), integer(), number()) :: :ok
  def insert(server, metric_name, labels, timestamp, value) do
    GenServer.call(server, {:insert, metric_name, labels, timestamp, value})
  end

  @doc """
  Returns the raw points for every series that matches `metric_name` and
  `label_matchers` within the inclusive range `{start_ts, end_ts}`.

  A series matches when it contains all key/value pairs in `label_matchers`
  (extra labels are allowed); an empty matcher map matches all series with the
  given metric name. The result is a list of `{labels, points}` tuples, where
  `points` are `{timestamp, value}` tuples sorted by timestamp. Series with no
  points in range are omitted entirely.
  """
  @spec query(GenServer.server(), String.t(), map(), {integer(), integer()}) :: [row()]
  def query(server, metric_name, label_matchers, {start_ts, end_ts}) do
    GenServer.call(server, {:query, metric_name, label_matchers, start_ts, end_ts})
  end

  @doc """
  Aggregates matched series over fixed windows of `step_ms` milliseconds.

  The half-open range `[start_ts, end_ts)` is divided into non-overlapping
  windows `[start_ts, start_ts + step_ms)`, and so on. For each matched series
  and window the given `aggregation` is computed over the points whose
  timestamps fall in that window:

    * `:avg` - arithmetic mean; empty windows omitted.
    * `:sum` - sum of values; empty windows omitted.
    * `:max` - maximum value; empty windows omitted.
    * `:rate` - `(last - first) / ((last_ts - first_ts) / 1000)`; windows with
      fewer than two points (or no time span) omitted.

  Returns `{labels, agg_points}` tuples where `agg_points` are
  `{window_start, value}` tuples sorted by time. Series with no resulting
  windows are omitted.
  """
  @spec query_agg(
          GenServer.server(),
          String.t(),
          map(),
          {integer(), integer()},
          :avg | :sum | :max | :rate,
          pos_integer()
        ) :: [row()]
  def query_agg(server, metric_name, label_matchers, {start_ts, end_ts}, aggregation, step_ms) do
    request = {:query_agg, metric_name, label_matchers, start_ts, end_ts, aggregation, step_ms}
    GenServer.call(server, request)
  end

  ## GenServer callbacks

  @impl true
  def init(opts) do
    default_clock = fn -> System.monotonic_time(:millisecond) end

    state = %{
      chunk_duration_ms: Keyword.get(opts, :chunk_duration_ms, @default_chunk_duration_ms),
      clock: Keyword.get(opts, :clock, default_clock),
      retention_ms: Keyword.get(opts, :retention_ms, @default_retention_ms),
      cleanup_interval_ms: Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms),
      series: %{}
    }

    schedule_cleanup(state)
    {:ok, state}
  end

  @impl true
  def handle_call({:insert, metric, labels, ts, value}, _from, state) do
    key = {metric, Enum.sort(Map.to_list(labels))}
    chunk_start = div(ts, state.chunk_duration_ms) * state.chunk_duration_ms
    chunks = Map.get(state.series, key, %{})
    points = Map.get(chunks, chunk_start, [])
    new_points = insert_point(points, {ts, value})
    new_chunks = Map.put(chunks, chunk_start, new_points)
    new_series = Map.put(state.series, key, new_chunks)
    {:reply, :ok, %{state | series: new_series}}
  end

  def handle_call({:query, metric, matchers, start_ts, end_ts}, _from, state) do
    result =
      for {{_metric, sorted_labels}, chunks} <- matching_series(state.series, metric, matchers),
          points = points_in_range(chunks, start_ts, end_ts),
          points != [] do
        {Map.new(sorted_labels), points}
      end

    {:reply, result, state}
  end

  def handle_call({:query_agg, metric, matchers, start_ts, end_ts, agg, step_ms}, _from, state) do
    windows = windows(start_ts, end_ts, step_ms)

    result =
      for {{_metric, sorted_labels}, chunks} <- matching_series(state.series, metric, matchers),
          agg_points = aggregate(chunks, windows, step_ms, agg),
          agg_points != [] do
        {Map.new(sorted_labels), agg_points}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    new_state = run_cleanup(state)
    schedule_cleanup(new_state)
    {:noreply, new_state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  ## Internal helpers

  @spec insert_point([point()], point()) :: [point()]
  defp insert_point([], point), do: [point]

  defp insert_point([{head_ts, _} = head | tail], {ts, _} = point) when head_ts <= ts do
    [head | insert_point(tail, point)]
  end

  defp insert_point(list, point), do: [point | list]

  @spec matching_series(map(), String.t(), map()) :: [{{String.t(), list()}, map()}]
  defp matching_series(series, metric, matchers) do
    Enum.filter(series, fn {{name, sorted_labels}, _chunks} ->
      name == metric and labels_match?(sorted_labels, matchers)
    end)
  end

  @spec labels_match?(list(), map()) :: boolean()
  defp labels_match?(sorted_labels, matchers) do
    labels = Map.new(sorted_labels)
    Enum.all?(matchers, fn {key, value} -> Map.get(labels, key) == value end)
  end

  @spec points_in_range(map(), integer(), integer()) :: [point()]
  defp points_in_range(chunks, start_ts, end_ts) do
    chunks
    |> Enum.flat_map(fn {_chunk_start, points} -> points end)
    |> Enum.filter(fn {ts, _value} -> ts >= start_ts and ts <= end_ts end)
    |> Enum.sort_by(fn {ts, _value} -> ts end)
  end

  @spec windows(integer(), integer(), pos_integer()) :: [integer()]
  defp windows(start_ts, end_ts, step_ms) do
    start_ts
    |> Stream.iterate(&(&1 + step_ms))
    |> Stream.take_while(&(&1 < end_ts))
    |> Enum.to_list()
  end

  @spec aggregate(map(), [integer()], pos_integer(), atom()) :: [point()]
  defp aggregate(chunks, windows, step_ms, agg) do
    all_points =
      chunks
      |> Enum.flat_map(fn {_chunk_start, points} -> points end)
      |> Enum.sort_by(fn {ts, _value} -> ts end)

    for window_start <- windows,
        window_points = window_points(all_points, window_start, step_ms),
        {:ok, value} <- [compute_agg(agg, window_points)] do
      {window_start, value}
    end
  end

  @spec window_points([point()], integer(), pos_integer()) :: [point()]
  defp window_points(points, window_start, step_ms) do
    window_end = window_start + step_ms
    Enum.filter(points, fn {ts, _value} -> ts >= window_start and ts < window_end end)
  end

  @spec compute_agg(atom(), [point()]) :: {:ok, number()} | :none
  defp compute_agg(_agg, []), do: :none

  defp compute_agg(:avg, points) do
    values = Enum.map(points, fn {_ts, value} -> value end)
    {:ok, Enum.sum(values) / length(values)}
  end

  defp compute_agg(:sum, points) do
    {:ok, Enum.sum(Enum.map(points, fn {_ts, value} -> value end))}
  end

  defp compute_agg(:max, points) do
    {:ok, Enum.max(Enum.map(points, fn {_ts, value} -> value end))}
  end

  defp compute_agg(:rate, points) when length(points) < 2, do: :none

  defp compute_agg(:rate, points) do
    {first_ts, first_value} = hd(points)
    {last_ts, last_value} = List.last(points)

    if last_ts == first_ts do
      :none
    else
      {:ok, (last_value - first_value) / ((last_ts - first_ts) / 1000)}
    end
  end

  @spec run_cleanup(map()) :: map()
  defp run_cleanup(state) do
    cutoff = state.clock.() - state.retention_ms

    new_series =
      state.series
      |> Enum.map(fn {key, chunks} -> {key, keep_live_chunks(chunks, cutoff, state)} end)
      |> Enum.reject(fn {_key, chunks} -> chunks == %{} end)
      |> Map.new()

    %{state | series: new_series}
  end

  @spec keep_live_chunks(map(), integer(), map()) :: map()
  defp keep_live_chunks(chunks, cutoff, state) do
    for {chunk_start, points} <- chunks,
        chunk_start + state.chunk_duration_ms >= cutoff,
        into: %{} do
      {chunk_start, points}
    end
  end

  @spec schedule_cleanup(map()) :: :ok
  defp schedule_cleanup(%{cleanup_interval_ms: :infinity}), do: :ok

  defp schedule_cleanup(%{cleanup_interval_ms: interval}) do
    Process.send_after(self(), :cleanup, interval)
    :ok
  end
end