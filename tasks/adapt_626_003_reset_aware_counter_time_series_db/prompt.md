# Rework this solution for a changed brief

The module below is a complete, tested solution to a neighboring task. Treat
it as your starting codebase, not as a suggestion — carry over what still
fits and rewrite what the new brief demands. Where old code and the new
specification conflict (module name, public API, behavior, constraints,
output format), the new specification is authoritative. Return the complete
final result.

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

# `CounterTSDB` — Reset-Aware Counter Time-Series Store

## Overview

This document specifies an Elixir GenServer module named `CounterTSDB`: a time-series storage engine specialized for **monotonic counters** — values that normally only increase, such as `http_requests_total`.

Unlike a plain gauge store, its range queries are **reset-aware**: when a counter is observed to drop, that drop is interpreted as a counter reset (the process restarted and the counter went back toward zero), not as a negative change.

## Public API

### `CounterTSDB.start_link(opts)`

Starts the process, returning `{:ok, pid}`. The following options are accepted:

- `:chunk_duration_ms` — the duration of each storage chunk in milliseconds (default `60_000`). Every unique series (metric name + exact label set) gets one chunk per time window.
- `:clock` — a zero-arity function returning the current time in milliseconds. Defaults to `fn -> System.monotonic_time(:millisecond) end`.
- `:name` — optional process registration name; when given, the process registers under it so every public API function can be called with that name in place of the pid.
- `:retention_ms` — how long chunks are kept before they become eligible for cleanup (default `3_600_000`).
- `:cleanup_interval_ms` — how often automatic cleanup of expired chunks runs via `Process.send_after` (default `60_000`). The value `:infinity` is accepted and disables it.

### `CounterTSDB.insert(server, metric_name, labels, timestamp, value)`

- `metric_name` is a string; `labels` is a map like `%{"instance" => "a"}`; `timestamp` is an integer in milliseconds; `value` is a number.
- The function returns `:ok`.
- The point is stored into the chunk identified by `chunk_start = div(timestamp, chunk_duration_ms) * chunk_duration_ms`. A series is identified by `{metric_name, sorted_labels}` where `sorted_labels = Enum.sort(Map.to_list(labels))`, so label ordering never creates duplicate series. Within each chunk, data points are stored sorted by timestamp. Two points may share the same timestamp; both are kept.

### `CounterTSDB.query(server, metric_name, label_matchers, {start_ts, end_ts})`

Returns raw samples.

- `label_matchers` is a map; a series matches if it contains **all** the specified key-value pairs (it may have additional labels). An empty map `%{}` matches all series with that metric name.
- The return value is a list of `{labels, points}` tuples, where `labels` is the series' label map as inserted (a map, not the sorted list used as the internal key) and `points` is the list of `{timestamp, value}` tuples for that series, sorted ascending by timestamp and filtered to `start_ts <= timestamp <= end_ts`.

### `CounterTSDB.query_range(server, metric_name, label_matchers, {start_ts, end_ts}, function, step_ms)`

- `function` is one of `:increase` or `:rate`.
- `step_ms` is the width of each window.
- The time range `[start_ts, end_ts)` is divided into non-overlapping windows of `step_ms` milliseconds: `[start_ts, start_ts + step_ms)`, `[start_ts + step_ms, start_ts + 2*step_ms)`, and so on.
- For each matched series and each window, the points whose timestamps fall in `[window_start, window_start + step_ms)` are taken, sorted ascending by timestamp. Then:
  - `:increase` — the total increase across the window, computed reset-aware. Consecutive point pairs `(prev_value, cur_value)` are walked in timestamp order; for each pair the contributed delta is `cur_value - prev_value` when `cur_value >= prev_value` (so two equal consecutive values contribute `0`, not a reset), otherwise (a reset is detected) the contributed delta is `cur_value` (treated as having climbed from zero to `cur_value`). The window's increase is the sum of these deltas, computed with plain arithmetic so integer samples yield an integer increase.
  - `:rate` — the reset-aware increase (computed exactly as above) divided by the elapsed seconds across the window: `increase / ((last_timestamp - first_timestamp) / 1000)`, where `first_timestamp`/`last_timestamp` are the smallest and largest timestamps of the points in that window.
- The return value is a list of `{labels, range_points}` tuples, where `labels` is the series' label map and `range_points` is a list of `{window_start, computed_value}` tuples sorted by window start.

## Cleanup

The server handles a `:cleanup` info message that removes any chunk whose `chunk_start + chunk_duration_ms` is less than or equal to `now - retention_ms` (where `now` comes from `:clock`). A series left with zero chunks is removed entirely.

This pass is also scheduled periodically using `Process.send_after` based on `:cleanup_interval_ms`: the first pass is scheduled at startup and the next one is scheduled after each pass runs, so cleanup keeps repeating on its own without anything sending `:cleanup`. Only cleanup consults `:clock`.

## Edge cases

- **`query/4`, series with no points in range:** a series that matches but has NO point in `[start_ts, end_ts]` is omitted entirely — it is never returned as `{labels, []}`.
- **`query/4`, nothing matches:** when nothing matches — no such metric name, or no series satisfying the matchers — the result is `[]`.
- **`query_range/6`, `:increase` with sparse windows:** if the window has fewer than 2 points, the window is omitted.
- **`query_range/6`, `:rate` with sparse or zero-span windows:** if the window has fewer than 2 points, or if `last_timestamp == first_timestamp`, the window is omitted (other windows of the same series still appear).
- **`query_range/6`, fully omitted series:** a matched series whose windows are all omitted is left out of the result entirely, so when nothing survives the result is `[]`.
- **Equal consecutive counter values:** these contribute `0` rather than being treated as a reset.
- **Label ordering:** because series keys use `sorted_labels`, differing label ordering never creates duplicate series.
- **Duplicate timestamps:** two points may share the same timestamp; both are kept.

## Constraints

- Only the OTP standard library may be used — no external dependencies.
- The complete module is to be provided in a single file.
- All operations go through the GenServer (`call`/`cast`) — no ETS, no separate processes.
