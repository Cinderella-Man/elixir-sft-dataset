# Write the missing @spec

Below is a complete, working module — except that the `@spec` for
`start_link/1` has been removed; its place is marked `# TODO: @spec`.
Write exactly that typespec: one `@spec` attribute for `start_link/1`,
consistent with the function's arguments, guards, and every return shape
the implementation can produce. Change nothing else.

## The module with the `@spec` for `start_link/1` missing

```elixir
defmodule CounterTSDB do
  @moduledoc """
  A GenServer-based time-series storage engine specialized for **monotonic
  counters** — values that normally only increase (for example
  `http_requests_total`).

  Points are stored per *series*, where a series is identified by a metric name
  together with an exact label set. Each series buckets its points into
  fixed-width time chunks. All state lives inside the GenServer; there is no
  ETS and there are no helper processes.

  Range queries (`increase`/`rate`) are **reset-aware**: when a counter is
  observed to drop between two consecutive samples, the drop is interpreted as a
  counter reset (the underlying process restarted and the counter climbed again
  from zero) rather than as a negative change.
  """

  use GenServer

  @type server :: GenServer.server()
  @type labels :: %{optional(String.t()) => term()}
  @type point :: {integer(), number()}
  @type range :: {integer(), integer()}
  @type function_kind :: :increase | :rate

  @default_chunk_duration_ms 60_000
  @default_retention_ms 3_600_000
  @default_cleanup_interval_ms 60_000

  # --------------------------------------------------------------------------
  # Public API
  # --------------------------------------------------------------------------

  @doc """
  Starts the storage engine.

  Options:

    * `:chunk_duration_ms` — width of each storage chunk (default `60_000`).
    * `:clock` — zero-arity function returning the current time in
      milliseconds (default `System.monotonic_time(:millisecond)`).
    * `:name` — optional process registration name.
    * `:retention_ms` — how long chunks are kept (default `3_600_000`).
    * `:cleanup_interval_ms` — how often automatic cleanup runs, or `:infinity`
      to disable (default `60_000`).
  """
  # TODO: @spec
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Inserts a single sample for the given metric and label set.

  The point is stored into the chunk identified by
  `div(timestamp, chunk_duration_ms) * chunk_duration_ms` and kept sorted by
  timestamp within that chunk. Always returns `:ok`.
  """
  @spec insert(server(), String.t(), labels(), integer(), number()) :: :ok
  def insert(server, metric_name, labels, timestamp, value) do
    GenServer.call(server, {:insert, metric_name, labels, timestamp, value})
  end

  @doc """
  Returns raw samples for series matching `metric_name` and `label_matchers`.

  A series matches when it contains all key/value pairs in `label_matchers`
  (extra labels are allowed); an empty map matches every series with the metric
  name. The result is a list of `{labels, points}` tuples where `points` is
  sorted ascending by timestamp and filtered to `start_ts <= ts <= end_ts`.
  Series with no point in range are omitted.
  """
  @spec query(server(), String.t(), labels(), range()) :: [{labels(), [point()]}]
  def query(server, metric_name, label_matchers, {start_ts, end_ts}) do
    GenServer.call(server, {:query, metric_name, label_matchers, {start_ts, end_ts}})
  end

  @doc """
  Computes reset-aware `:increase` or `:rate` over stepped windows.

  The range `[start_ts, end_ts)` is split into non-overlapping windows of
  `step_ms`. For each matched series and window, the points in
  `[window_start, window_start + step_ms)` are used to compute the value.
  Returns a list of `{labels, range_points}` tuples; series whose windows are
  all omitted are excluded.
  """
  @spec query_range(server(), String.t(), labels(), range(), function_kind(), pos_integer()) ::
          [{labels(), [{integer(), number()}]}]
  def query_range(server, metric_name, label_matchers, {start_ts, end_ts}, function, step_ms) do
    request =
      {:query_range, metric_name, label_matchers, {start_ts, end_ts}, function, step_ms}

    GenServer.call(server, request)
  end

  # --------------------------------------------------------------------------
  # GenServer callbacks
  # --------------------------------------------------------------------------

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

    schedule_cleanup(state.cleanup_interval_ms)
    {:ok, state}
  end

  @impl true
  def handle_call({:insert, metric, labels, ts, value}, _from, state) do
    key = series_key(metric, labels)
    chunk_start = div(ts, state.chunk_duration_ms) * state.chunk_duration_ms

    entry = Map.get(state.series, key, %{labels: labels, chunks: %{}})
    chunk = Map.get(entry.chunks, chunk_start, [])
    chunk = insert_by_ts(chunk, ts, {ts, value})
    entry = %{entry | chunks: Map.put(entry.chunks, chunk_start, chunk)}

    {:reply, :ok, %{state | series: Map.put(state.series, key, entry)}}
  end

  def handle_call({:query, metric, matchers, range}, _from, state) do
    {start_ts, end_ts} = range

    result =
      state
      |> matching_series(metric, matchers)
      |> Enum.map(fn entry ->
        points =
          entry
          |> series_points()
          |> Enum.filter(fn {ts, _v} -> ts >= start_ts and ts <= end_ts end)

        {entry.labels, points}
      end)
      |> Enum.reject(fn {_labels, points} -> points == [] end)

    {:reply, result, state}
  end

  def handle_call({:query_range, metric, matchers, range, fun, step}, _from, state) do
    {start_ts, end_ts} = range
    wins = windows(start_ts, end_ts, step)

    result =
      state
      |> matching_series(metric, matchers)
      |> Enum.map(fn entry ->
        all_points = series_points(entry)

        range_points =
          Enum.flat_map(wins, fn window_start ->
            window_end = window_start + step

            points =
              Enum.filter(all_points, fn {ts, _v} ->
                ts >= window_start and ts < window_end
              end)

            case compute(fun, points) do
              :omit -> []
              {:ok, value} -> [{window_start, value}]
            end
          end)

        {entry.labels, range_points}
      end)
      |> Enum.reject(fn {_labels, range_points} -> range_points == [] end)

    {:reply, result, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    new_state = cleanup(state)
    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, new_state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # --------------------------------------------------------------------------
  # Internal helpers
  # --------------------------------------------------------------------------

  @spec series_key(String.t(), labels()) :: {String.t(), [{term(), term()}]}
  defp series_key(metric, labels), do: {metric, Enum.sort(Map.to_list(labels))}

  @spec insert_by_ts([point()], integer(), point()) :: [point()]
  defp insert_by_ts([], _ts, point), do: [point]

  defp insert_by_ts([{head_ts, _v} = head | rest], ts, point) when head_ts <= ts do
    [head | insert_by_ts(rest, ts, point)]
  end

  defp insert_by_ts(list, _ts, point), do: [point | list]

  @spec matching_series(map(), String.t(), labels()) :: [map()]
  defp matching_series(state, metric, matchers) do
    state.series
    |> Enum.filter(fn {{name, _sorted}, entry} ->
      name == metric and matches?(entry.labels, matchers)
    end)
    |> Enum.map(fn {_key, entry} -> entry end)
  end

  @spec matches?(labels(), labels()) :: boolean()
  defp matches?(labels, matchers) do
    Enum.all?(matchers, fn {k, v} -> Map.get(labels, k) == v end)
  end

  @spec series_points(map()) :: [point()]
  defp series_points(entry) do
    entry.chunks
    |> Map.values()
    |> Enum.concat()
    |> Enum.sort_by(fn {ts, _v} -> ts end)
  end

  @spec windows(integer(), integer(), pos_integer()) :: [integer()]
  defp windows(start_ts, end_ts, _step) when start_ts >= end_ts, do: []

  defp windows(start_ts, end_ts, step) do
    start_ts
    |> Stream.iterate(&(&1 + step))
    |> Enum.take_while(&(&1 < end_ts))
  end

  @spec compute(function_kind(), [point()]) :: :omit | {:ok, number()}
  defp compute(:increase, points) when length(points) < 2, do: :omit
  defp compute(:increase, points), do: {:ok, reset_aware_increase(points)}

  defp compute(:rate, points) when length(points) < 2, do: :omit

  defp compute(:rate, points) do
    {first_ts, _v} = hd(points)
    {last_ts, _w} = List.last(points)

    if last_ts == first_ts do
      :omit
    else
      increase = reset_aware_increase(points)
      {:ok, increase / ((last_ts - first_ts) / 1000)}
    end
  end

  @spec reset_aware_increase([point()]) :: number()
  defp reset_aware_increase(points) do
    points
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce(0, fn [{_pts, prev}, {_cts, cur}], acc ->
      delta = if cur >= prev, do: cur - prev, else: cur
      acc + delta
    end)
  end

  @spec cleanup(map()) :: map()
  defp cleanup(state) do
    now = state.clock.()
    threshold = now - state.retention_ms

    new_series =
      state.series
      |> Enum.map(fn {key, entry} ->
        kept =
          entry.chunks
          |> Enum.reject(fn {chunk_start, _points} ->
            chunk_start + state.chunk_duration_ms <= threshold
          end)
          |> Map.new()

        {key, %{entry | chunks: kept}}
      end)
      |> Enum.reject(fn {_key, entry} -> map_size(entry.chunks) == 0 end)
      |> Map.new()

    %{state | series: new_series}
  end

  @spec schedule_cleanup(:infinity | non_neg_integer()) :: :ok | reference()
  defp schedule_cleanup(:infinity), do: :ok
  defp schedule_cleanup(interval), do: Process.send_after(self(), :cleanup, interval)
end
```

Give me only the `@spec` attribute — the attribute alone (however many
lines it spans), not the whole module.
