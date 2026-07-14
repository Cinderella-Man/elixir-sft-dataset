# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

## Existing code (your starting point)

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

    {:ok, state}
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

## New specification

Write me an Elixir GenServer module called `RollupTSDB` that implements a time-series storage engine that **pre-aggregates data on ingest** instead of keeping raw samples. Rather than storing every data point, each series keeps one compact *rollup accumulator* per fixed-width time bucket, so memory use per bucket is constant no matter how many points land in it.

## Public API

- `RollupTSDB.start_link(opts)` to start the process. It should accept:
  - `:bucket_duration_ms` — the width of each rollup bucket in milliseconds (default `60_000`, i.e. one minute). Every unique series (metric name + exact label set) gets one rollup accumulator per time bucket.
  - `:clock` — a zero-arity function returning the current time in milliseconds. Default to `fn -> System.monotonic_time(:millisecond) end`.
  - `:name` — optional process registration name.
  - `:retention_ms` — how long to keep buckets before they are eligible for cleanup (default `3_600_000`, i.e. one hour).
  - `:cleanup_interval_ms` — how often to run automatic cleanup of expired buckets via `Process.send_after` (default `60_000`). Accept `:infinity` to disable.

- `RollupTSDB.insert(server, metric_name, labels, timestamp, value)` where:
  - `metric_name` is a string like `"http_requests_total"`.
  - `labels` is a map like `%{"method" => "GET", "status" => "200"}`.
  - `timestamp` is an integer in milliseconds.
  - `value` is a number (integer or float).
  - The function should return `:ok`.
  - The point is folded into the rollup accumulator for the bucket identified by `bucket_start = div(timestamp, bucket_duration_ms) * bucket_duration_ms`. A series is identified by the tuple `{metric_name, sorted_labels}`, where `sorted_labels = Enum.sort(Map.to_list(labels))`, so label ordering never creates duplicate series.
  - **No raw points are stored.** Each bucket's accumulator is updated in place as follows (the first point to arrive in a bucket seeds the accumulator; each later point folds in):
    - `count` — number of points folded in so far.
    - `sum` — running sum of values.
    - `min` — smallest value seen.
    - `max` — largest value seen.
    - `first` — the value of the point with the **smallest timestamp** folded into the bucket. On a tie for the smallest timestamp, the earliest-arriving point wins (i.e. only replace `first` when a strictly smaller timestamp arrives).
    - `last` — the value of the point with the **largest timestamp** folded into the bucket. On a tie for the largest timestamp, the latest-arriving point wins (i.e. replace `last` whenever a timestamp greater than or equal to the current largest arrives).

- `RollupTSDB.query(server, metric_name, label_matchers, {start_ts, end_ts})` where:
  - `label_matchers` is a map of label key-value pairs. A series matches if it contains **all** of the specified key-value pairs (it may have additional labels). An empty map `%{}` matches all series with that metric name.
  - The return value is a list of `{labels, buckets}` tuples, where `labels` is the full label map for that series and `buckets` is a list of `{bucket_start, stats}` tuples, sorted ascending by `bucket_start`, and restricted to buckets whose `bucket_start` satisfies `start_ts <= bucket_start <= end_ts`.
  - `stats` is a map with exactly these keys:
    - `:count`, `:sum`, `:min`, `:max` — as accumulated above.
    - `:avg` — `sum / count` (a float).
    - `:first`, `:last` — as accumulated above.
  - A series that matches but which has NO bucket in the `[start_ts, end_ts]` range must be omitted from the result entirely — never returned as a `{labels, []}` tuple. When no matched series has any bucket in range, the result is `[]`.

## Cleanup

Handle a `:cleanup` info message that removes any bucket whose `bucket_start + bucket_duration_ms` is less than or equal to `now - retention_ms` (where `now` comes from `:clock`). A series left with zero buckets after cleanup is removed entirely. Also schedule this periodically using `Process.send_after` based on `:cleanup_interval_ms`.

## Constraints

- Use only OTP standard library — no external dependencies.
- Give me the complete module in a single file.
- All operations go through the GenServer (`call`/`cast`) — no ETS, no separate processes.
