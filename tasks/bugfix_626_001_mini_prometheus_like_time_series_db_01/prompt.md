# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

**TSDB — chunked in-memory time-series storage engine (Elixir GenServer)**

Implement a GenServer module `TSDB` providing a metrics-optimized time-series store using a chunked in-memory storage format.

**Startup — `TSDB.start_link(opts)`**
- `opts` is a keyword list; returns `{:ok, pid}` on success.
- `:chunk_duration_ms` — duration of each storage chunk in milliseconds; default `60_000` (one minute). Every unique series (metric name + exact label set) gets one chunk per time window.
- `:clock` — zero-arity function returning current time in milliseconds; default `fn -> System.monotonic_time(:millisecond) end`.
- `:name` — optional process registration name. When absent, the process must still start unnamed; do not pass `name: nil` through to `GenServer.start_link/3`.
- `:retention_ms` — how long chunks are kept before becoming eligible for cleanup; default `3_600_000` (one hour).
- `:cleanup_interval_ms` — how often automatic cleanup of expired chunks runs via `Process.send_after`; default `60_000`. `:infinity` must be accepted and disables scheduling entirely.

**Ingest — `TSDB.insert(server, metric_name, labels, timestamp, value)`**
- `metric_name`: string, e.g. `"http_requests_total"`.
- `labels`: map, e.g. `%{"method" => "GET", "status" => "200"}`; may be empty (`%{}`).
- `timestamp`: integer milliseconds.
- `value`: number (integer or float). Store and return values exactly as given — never coerce between integer and float.
- Returns `:ok`.
- Routes the data point into the correct chunk from `timestamp` and `chunk_duration_ms`. A chunk is identified by `{metric_name, sorted_labels, chunk_start}` with `chunk_start = div(timestamp, chunk_duration_ms) * chunk_duration_ms` — so with `chunk_duration_ms = 1_000`, `t = 1000` belongs to chunk `1000`, not chunk `0`.
- Within each chunk, data points are stored sorted by timestamp.

**Raw read — `TSDB.query(server, metric_name, label_matchers, {start_ts, end_ts})`**
- `label_matchers`: map of label key-value pairs. A series matches when it contains **all** specified key-value pairs; extra labels are allowed. An empty map `%{}` matches all series with that metric name.
- Returns a list of `{labels, points}` tuples. `labels` is the series' full label map (e.g. `%{"host" => "a"}`, or `%{}` for a series inserted with empty labels). `points` is a list of `{timestamp, value}` tuples sorted ascending by timestamp, filtered to `start_ts <= timestamp <= end_ts` (both bounds inclusive).

**Aggregated read — `TSDB.query_agg(server, metric_name, label_matchers, {start_ts, end_ts}, aggregation, step_ms)`**
- `aggregation` is one of `:avg`, `:sum`, `:max`, `:rate`. `step_ms` is the width of each aggregation window.
- Divide `[start_ts, end_ts)` into non-overlapping windows of `step_ms` milliseconds: `[start_ts, start_ts + step_ms)`, `[start_ts + step_ms, start_ts + 2*step_ms)`, etc. A point falls in a window when `window_start <= timestamp < window_start + step_ms`.
- Per matched series, per window, aggregate over the data points whose timestamps land in that window:
  - `:avg` — arithmetic mean of values, a float. Window with no points is omitted from the output.
  - `:sum` — sum of values with no numeric coercion: summing integers yields an integer (`10 + 20 + 30` is `60`, not `60.0`). Window with no points is omitted.
  - `:max` — maximum value returned as stored (integer stays integer). Window with no points is omitted.
  - `:rate` — per-second rate of change as a float, computed as `(last_value - first_value) / ((last_timestamp - first_timestamp) / 1000)`. Window with fewer than 2 points is omitted.
- Return shape matches `query/4`: a list of `{labels, agg_points}` tuples, `agg_points` being `{window_start_timestamp, aggregated_value}` tuples sorted by time. A matched series whose windows are all omitted is itself dropped from the result; when nothing matches, the result is `[]`.

**Storage layout**
- Nested map keyed by `{metric_name, sorted_labels}` (the "series key"); each series key maps to a map of `chunk_start => [sorted data points]`.
- Produce sorted labels by converting the labels map to a sorted keyword-style list (e.g. `Enum.sort(Map.to_list(labels))`) so label ordering never creates duplicate series — inserting with `%{"a" => "1", "b" => "2"}` and with `%{"b" => "2", "a" => "1"}` must land in one and the same series.

**Cleanup**
- Handle a `:cleanup` info message, delivered both by the periodic timer and directly via `send(pid, :cleanup)`.
- Remove any chunk where `chunk_start + chunk_duration_ms <= now - retention_ms`, with `now` from the configured `:clock`.
- A series left with no chunks is removed entirely and no longer appears in any `query/4` or `query_agg/6` result.
- Schedule cleanup periodically with `Process.send_after` based on `:cleanup_interval_ms`.

**Constraints**
- OTP standard library only — no external dependencies.
- Complete module delivered in a single file.
- All operations go through the GenServer (`call`/`cast`) — no ETS, no separate processes.

**Interface contract — empty results**
- In `query/4`, a series whose labels match but which has NO data points inside `[start_ts, end_ts]` is omitted from the result entirely — never returned as a `{labels, []}` tuple with an empty points list.
- When no matched series has any point in range, and when the metric name is unknown, the result is `[]`.

## The buggy module

```elixir
defmodule TSDB do
  @moduledoc """
  A time-series storage engine implemented as a GenServer.

  Data is stored in chunked, in-memory format. Each unique series
  (metric_name + sorted label set) owns one chunk per time window.
  Within each chunk, data points are kept sorted by timestamp.

  ## Storage layout

      %{
        series: %{
          {metric_name, sorted_labels} => %{
            chunk_start => [{timestamp, value}, ...]
          }
        }
      }
  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Types
  # ---------------------------------------------------------------------------

  @type metric_name :: String.t()
  @type labels :: %{String.t() => String.t()}
  @type timestamp :: integer()
  @type value :: number()
  @type series_key :: {metric_name(), list()}
  @type chunk_key :: non_neg_integer()
  @type point :: {timestamp(), value()}

  @type state :: %{
          series: %{series_key() => %{chunk_key() => [point()]}},
          chunk_duration_ms: pos_integer(),
          retention_ms: pos_integer(),
          cleanup_interval_ms: pos_integer() | :infinity,
          clock: (-> integer())
        }

  # ---------------------------------------------------------------------------
  # Default options
  # ---------------------------------------------------------------------------

  @default_chunk_duration_ms 60_000
  @default_retention_ms 3_600_000
  @default_cleanup_interval_ms 60_000

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name_opts, init_opts} =
      case Keyword.pop(opts, :name) do
        {nil, rest} -> {[], rest}
        {name, rest} -> {[name: name], rest}
      end

    GenServer.start_link(__MODULE__, init_opts, name_opts)
  end

  @doc """
  Insert a single data point into the store.
  """
  @spec insert(GenServer.server(), metric_name(), labels(), timestamp(), value()) :: :ok
  def insert(server, metric_name, labels, timestamp, value) do
    GenServer.cast(server, {:insert, metric_name, labels, timestamp, value})
  end

  @doc """
  Query raw data points for a metric, filtered by label matchers and time range.

  Returns `[{labels, [{timestamp, value}]}]`.
  """
  @spec query(GenServer.server(), metric_name(), labels(), {timestamp(), timestamp()}) ::
          [{labels(), [point()]}]
  def query(server, metric_name, label_matchers, {start_ts, end_ts}) do
    GenServer.call(server, {:query, metric_name, label_matchers, start_ts, end_ts})
  end

  @doc """
  Query aggregated data points over fixed-width windows.

  `aggregation` is one of `:avg`, `:sum`, `:max`, `:rate`.
  `step_ms` is the window width in milliseconds.

  Returns `[{labels, [{window_start, aggregated_value}]}]`.
  """
  @spec query_agg(
          GenServer.server(),
          metric_name(),
          labels(),
          {timestamp(), timestamp()},
          :avg | :sum | :max | :rate,
          pos_integer()
        ) :: [{labels(), [point()]}]
  def query_agg(server, metric_name, label_matchers, {start_ts, end_ts}, aggregation, step_ms) do
    GenServer.call(
      server,
      {:query_agg, metric_name, label_matchers, start_ts, end_ts, aggregation, step_ms}
    )
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    chunk_duration_ms = Keyword.get(opts, :chunk_duration_ms, @default_chunk_duration_ms)
    retention_ms = Keyword.get(opts, :retention_ms, @default_retention_ms)
    cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)

    state = %{
      series: %{},
      chunk_duration_ms: chunk_duration_ms,
      retention_ms: retention_ms,
      cleanup_interval_ms: cleanup_interval_ms,
      clock: clock
    }

    schedule_cleanup(state)

    {:error, state}
  end

  @impl true
  def handle_cast({:insert, metric_name, labels, timestamp, value}, state) do
    sorted_labels = Enum.sort(Map.to_list(labels))
    series_key = {metric_name, sorted_labels}
    chunk_start = chunk_start_for(timestamp, state.chunk_duration_ms)

    new_series =
      Map.update(state.series, series_key, %{chunk_start => [{timestamp, value}]}, fn series ->
        Map.update(series, chunk_start, [{timestamp, value}], fn points ->
          insert_sorted(points, {timestamp, value})
        end)
      end)

    {:noreply, %{state | series: new_series}}
  end

  @impl true
  def handle_call({:query, metric_name, label_matchers, start_ts, end_ts}, _from, state) do
    result = do_query(state, metric_name, label_matchers, start_ts, end_ts)
    {:reply, result, state}
  end

  @impl true
  def handle_call(
        {:query_agg, metric_name, label_matchers, start_ts, end_ts, aggregation, step_ms},
        _from,
        state
      ) do
    raw = do_query(state, metric_name, label_matchers, start_ts, end_ts)

    result =
      Enum.flat_map(raw, fn {labels, points} ->
        agg_points = aggregate(points, start_ts, end_ts, aggregation, step_ms)

        if agg_points == [] do
          []
        else
          [{labels, agg_points}]
        end
      end)

    {:reply, result, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    new_state = do_cleanup(state)
    schedule_cleanup(new_state)
    {:noreply, new_state}
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  # --- Chunk helpers ---

  defp chunk_start_for(timestamp, chunk_duration_ms) do
    div(timestamp, chunk_duration_ms) * chunk_duration_ms
  end

  # --- Sorted insertion ---
  # Inserts a point into a sorted list, maintaining ascending timestamp order.
  # For duplicate timestamps the new value is appended after existing ones.

  defp insert_sorted([], point), do: [point]

  defp insert_sorted([{ts, _} = head | tail] = list, {new_ts, _} = point) do
    if new_ts < ts do
      [point | list]
    else
      [head | insert_sorted(tail, point)]
    end
  end

  # --- Query ---

  defp do_query(state, metric_name, label_matchers, start_ts, end_ts) do
    chunk_duration_ms = state.chunk_duration_ms

    # Find the chunk windows that overlap [start_ts, end_ts]
    first_chunk = chunk_start_for(start_ts, chunk_duration_ms)
    last_chunk = chunk_start_for(end_ts, chunk_duration_ms)

    Enum.flat_map(state.series, fn {{m, sorted_labels}, series} ->
      if m != metric_name do
        []
      else
        labels_map = Map.new(sorted_labels)

        if labels_match?(labels_map, label_matchers) do
          # Collect points from all relevant chunks
          points =
            series
            |> Enum.filter(fn {chunk_start, _} ->
              chunk_start >= first_chunk and chunk_start <= last_chunk
            end)
            |> Enum.flat_map(fn {_chunk_start, pts} -> pts end)
            |> Enum.filter(fn {ts, _} -> ts >= start_ts and ts <= end_ts end)
            |> Enum.sort_by(fn {ts, _} -> ts end)

          if points == [] do
            []
          else
            [{labels_map, points}]
          end
        else
          []
        end
      end
    end)
  end

  defp labels_match?(_labels, matchers) when map_size(matchers) == 0, do: true

  defp labels_match?(labels, matchers) do
    Enum.all?(matchers, fn {k, v} -> Map.get(labels, k) == v end)
  end

  # --- Aggregation ---

  defp aggregate(points, start_ts, end_ts, aggregation, step_ms) do
    windows = build_windows(start_ts, end_ts, step_ms)

    Enum.flat_map(windows, fn window_start ->
      window_end = window_start + step_ms

      window_points =
        Enum.filter(points, fn {ts, _} ->
          ts >= window_start and ts < window_end
        end)

      case compute_agg(window_points, aggregation) do
        nil -> []
        agg_value -> [{window_start, agg_value}]
      end
    end)
  end

  defp build_windows(start_ts, end_ts, step_ms) do
    Stream.iterate(start_ts, &(&1 + step_ms))
    |> Stream.take_while(&(&1 < end_ts))
    |> Enum.to_list()
  end

  defp compute_agg([], _agg), do: nil
  defp compute_agg([_], :rate), do: nil

  defp compute_agg(points, :avg) do
    values = Enum.map(points, fn {_, v} -> v end)
    Enum.sum(values) / length(values)
  end

  defp compute_agg(points, :sum) do
    points |> Enum.map(fn {_, v} -> v end) |> Enum.sum()
  end

  defp compute_agg(points, :max) do
    points |> Enum.map(fn {_, v} -> v end) |> Enum.max()
  end

  defp compute_agg(points, :rate) do
    {first_ts, first_v} = List.first(points)
    {last_ts, last_v} = List.last(points)

    if last_ts == first_ts do
      nil
    else
      (last_v - first_v) / ((last_ts - first_ts) / 1000)
    end
  end

  # --- Cleanup ---

  defp do_cleanup(state) do
    now = state.clock.()
    cutoff = now - state.retention_ms
    chunk_duration_ms = state.chunk_duration_ms

    new_series =
      state.series
      |> Enum.reduce(%{}, fn {series_key, series}, acc ->
        trimmed =
          series
          |> Enum.reject(fn {chunk_start, _} ->
            # A chunk is expired when its end (chunk_start + chunk_duration_ms) <= cutoff
            chunk_start + chunk_duration_ms <= cutoff
          end)
          |> Map.new()

        if map_size(trimmed) == 0 do
          acc
        else
          Map.put(acc, series_key, trimmed)
        end
      end)

    %{state | series: new_series}
  end

  defp schedule_cleanup(%{cleanup_interval_ms: :infinity}), do: :ok

  defp schedule_cleanup(%{cleanup_interval_ms: interval_ms}) do
    Process.send_after(self(), :cleanup, interval_ms)
  end
end
```

## Failing test report

```
23 of 23 test(s) failed:

  * test insert and retrieve a single data point
      no match of right hand side value:
      
          {:error,
           %{
             series: %{},
             chunk_duration_ms: 1000,
             retention_ms: 10000,
             cleanup_interval_ms: :infinity,
             clock: &TSDBTest.Clock.now/0
           }}
      

  * test multiple points in the same series are sorted by timestamp
      no match of right hand side value:
      
          {:error,
           %{
             series: %{},
             chunk_duration_ms: 1000,
             retention_ms: 10000,
             cleanup_interval_ms: :infinity,
             clock: &TSDBTest.Clock.now/0
           }}
      

  * test query filters by time range (inclusive bounds)
      no match of right hand side value:
      
          {:error,
           %{
             series: %{},
             chunk_duration_ms: 1000,
             retention_ms: 10000,
             cleanup_interval_ms: :infinity,
             clock: &TSDBTest.Clock.now/0
           }}
      

  * test query returns empty list when no data matches
      no match of right hand side value:
      
          {:error,
           %{
             series: %{},
             chunk_duration_ms: 1000,
             retention_ms: 10000,
             cleanup_interval_ms: :infinity,
             clock: &TSDBTest.Clock.now/0
           }}
      

  (…19 more)
```
