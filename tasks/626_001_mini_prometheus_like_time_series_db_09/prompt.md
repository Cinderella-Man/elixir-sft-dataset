# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `init` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir GenServer module called `TSDB` that implements a time-series storage engine optimized for metrics, using a chunked in-memory storage format.

## Public API

- `TSDB.start_link(opts)` to start the process, where `opts` is a keyword list. It returns `{:ok, pid}` on success. It should accept:
  - `:chunk_duration_ms` — the duration of each storage chunk in milliseconds (default `60_000`, i.e. one minute). Every unique series (metric name + exact label set) gets one chunk per time window.
  - `:clock` — a zero-arity function returning the current time in milliseconds. Default to `fn -> System.monotonic_time(:millisecond) end`.
  - `:name` — optional process registration name. When absent, the process must still start unnamed (don't pass `name: nil` through to `GenServer.start_link/3`).
  - `:retention_ms` — how long to keep chunks before they are eligible for cleanup (default `3_600_000`, i.e. one hour).
  - `:cleanup_interval_ms` — how often to run automatic cleanup of expired chunks via `Process.send_after` (default `60_000`). Accept `:infinity` to disable scheduling entirely.

- `TSDB.insert(server, metric_name, labels, timestamp, value)` where:
  - `metric_name` is a string like `"http_requests_total"`.
  - `labels` is a map like `%{"method" => "GET", "status" => "200"}`. It may be empty (`%{}`).
  - `timestamp` is an integer in milliseconds.
  - `value` is a number (integer or float). Values must be stored and returned exactly as given — never coerced between integer and float.
  - The function should return `:ok`.
  - Internally, the data point must be placed into the correct chunk based on `timestamp` and `chunk_duration_ms`. A chunk is identified by the tuple `{metric_name, sorted_labels, chunk_start}` where `chunk_start = div(timestamp, chunk_duration_ms) * chunk_duration_ms` (so with `chunk_duration_ms = 1_000`, `t = 1000` belongs to chunk `1000`, not chunk `0`). Within each chunk, data points must be stored sorted by timestamp.

- `TSDB.query(server, metric_name, label_matchers, {start_ts, end_ts})` where:
  - `label_matchers` is a map of label key-value pairs. A series matches if it contains **all** of the specified key-value pairs (it may have additional labels). An empty map `%{}` matches all series with that metric name.
  - The return value is a list of `{labels, points}` tuples, where `labels` is the full label map for that series (a map, e.g. `%{"host" => "a"}`, or `%{}` for a series inserted with empty labels) and `points` is a list of `{timestamp, value}` tuples, sorted ascending by timestamp, filtered to `start_ts <= timestamp <= end_ts` (both bounds inclusive).

- `TSDB.query_agg(server, metric_name, label_matchers, {start_ts, end_ts}, aggregation, step_ms)` where:
  - `aggregation` is one of `:avg`, `:sum`, `:max`, `:rate`.
  - `step_ms` is the width of each aggregation window.
  - The function divides the time range `[start_ts, end_ts)` into non-overlapping windows of `step_ms` milliseconds: `[start_ts, start_ts + step_ms)`, `[start_ts + step_ms, start_ts + 2*step_ms)`, etc. A point falls in a window when `window_start <= timestamp < window_start + step_ms`.
  - For each matched series and each window, compute the aggregation over data points whose timestamps fall within that window:
    - `:avg` — arithmetic mean of values (a float). If the window has no points, the window is omitted from the output.
    - `:sum` — sum of values, with no numeric coercion: summing integers yields an integer (e.g. `10 + 20 + 30` is `60`, not `60.0`). If the window has no points, the window is omitted.
    - `:max` — maximum value, returned as stored (integer stays integer). If the window has no points, the window is omitted.
    - `:rate` — per-second rate of change, as a float. Computed as `(last_value - first_value) / ((last_timestamp - first_timestamp) / 1000)`. If a window has fewer than 2 points, the window is omitted.
  - The return value has the same shape as `query/4`: a list of `{labels, agg_points}` tuples, where `agg_points` is a list of `{window_start_timestamp, aggregated_value}` tuples sorted by time. A matched series whose windows all get omitted is itself dropped from the result, and when nothing matches the result is `[]`.

## Storage Design

Internally, use a nested map structure keyed by `{metric_name, sorted_labels}` (the "series key"), where each series key maps to a map of `chunk_start => [sorted data points]`. The sorted labels should be produced by converting the labels map to a sorted keyword-style list (e.g. `Enum.sort(Map.to_list(labels))`) so that label ordering doesn't create duplicate series — inserting with `%{"a" => "1", "b" => "2"}` and with `%{"b" => "2", "a" => "1"}` must land in one and the same series.

## Cleanup

Handle a `:cleanup` info message (sent both by the periodic timer and directly via `send(pid, :cleanup)`) that removes any chunk for which `chunk_start + chunk_duration_ms <= now - retention_ms`, where `now` comes from the configured `:clock`. A series left with no chunks is removed entirely, so it no longer appears in any `query/4` or `query_agg/6` result. Also schedule this periodically using `Process.send_after` based on `:cleanup_interval_ms`.

## Constraints

- Use only OTP standard library — no external dependencies.
- Give me the complete module in a single file.
- All operations go through the GenServer (`call`/`cast`) — no ETS, no separate processes.

## Additional interface contract

- In `query/4`, a series whose labels match but which has NO data points inside `[start_ts, end_ts]` must be omitted from the result entirely — never returned as a `{labels, []}` tuple with an empty points list. When no matched series has any point in range, and when the metric name is unknown, the result is `[]`.

## The module with `init` missing

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

  def init(opts) do
    # TODO
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

Give me only the complete implementation of `init` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
