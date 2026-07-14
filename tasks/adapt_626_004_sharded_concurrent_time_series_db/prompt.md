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

Write me an Elixir module called `ShardedTSDB` that implements a time-series storage engine whose data is **horizontally sharded across several worker processes**. A single coordinator GenServer owns a fixed set of shard GenServers; each series lives on exactly one shard, writes route to the owning shard, and reads fan out across all shards and merge.

## Architecture

- Starting the engine starts one coordinator process plus `:shards` independent worker (shard) GenServers. `start_link/1` returns the coordinator; all public functions take the coordinator as their `server` argument.
- A series is identified by `{metric_name, sorted_labels}` where `sorted_labels = Enum.sort(Map.to_list(labels))`, so label ordering never creates duplicate series.
- The shard index that owns a series is `:erlang.phash2({metric_name, sorted_labels}, shard_count)`, a 0-based integer in `0..(shard_count - 1)`.
- Each shard stores its own series independently using the layout: series key → `%{chunk_start => sorted data points}`, with `chunk_start = div(timestamp, chunk_duration_ms) * chunk_duration_ms`, and points within a chunk kept sorted by timestamp.

## Public API

- `ShardedTSDB.start_link(opts)` accepting:
  - `:shards` — the number of shard worker processes to start (default `4`).
  - `:chunk_duration_ms` — chunk width in milliseconds (default `60_000`).
  - `:clock` — a zero-arity function returning the current time in milliseconds. Default to `fn -> System.monotonic_time(:millisecond) end`.
  - `:name` — optional registration name for the coordinator.
  - `:retention_ms` — how long to keep chunks before cleanup (default `3_600_000`).
  - `:cleanup_interval_ms` — how often the coordinator triggers cleanup across all shards via `Process.send_after` (default `60_000`). Accept `:infinity` to disable.

- `ShardedTSDB.insert(server, metric_name, labels, timestamp, value)` — routes the point to the owning shard and returns `:ok`.

- `ShardedTSDB.query(server, metric_name, label_matchers, {start_ts, end_ts})` — fans out to all shards and merges results. `label_matchers` is a map; a series matches if it contains **all** the specified key-value pairs (it may have more). `%{}` matches all series with that metric name. Returns a list of `{labels, points}` tuples, where `points` is the `{timestamp, value}` list for that series sorted ascending by timestamp and filtered to `start_ts <= timestamp <= end_ts`. A matched series with no point in range is omitted entirely; when nothing matches, the result is `[]`. The order of series in the merged list is unspecified.

- `ShardedTSDB.query_agg(server, metric_name, label_matchers, {start_ts, end_ts}, aggregation, step_ms)` where:
  - `aggregation` is one of `:sum`, `:avg`, `:max`.
  - `step_ms` is the window width. The range `[start_ts, end_ts)` is divided into non-overlapping windows `[start_ts, start_ts + step_ms)`, `[start_ts + step_ms, start_ts + 2*step_ms)`, etc.
  - For each matched series and each window, take the points whose timestamps fall in `[window_start, window_start + step_ms)` and compute:
    - `:sum` — the sum of values; omit the window if it has no points.
    - `:avg` — the arithmetic mean of values; omit the window if it has no points.
    - `:max` — the maximum value; omit the window if it has no points.
  - Returns a list of `{labels, agg_points}` tuples, where `agg_points` is a list of `{window_start, aggregated_value}` tuples sorted by window start. A matched series whose windows are all omitted is left out of the result.

## Introspection helpers

- `ShardedTSDB.shard_count(server)` — returns the configured number of shards.
- `ShardedTSDB.shard_of(server, metric_name, labels)` — returns the 0-based shard index that owns the given series, i.e. `:erlang.phash2({metric_name, Enum.sort(Map.to_list(labels))}, shard_count)`.
- `ShardedTSDB.series_count(server)` — returns the total number of distinct series stored across all shards.
- `ShardedTSDB.cleanup(server)` — synchronously runs cleanup across all shards and returns `:ok`. Cleanup removes any chunk whose `chunk_start + chunk_duration_ms` is less than or equal to `now - retention_ms` (where `now` comes from `:clock`), and drops any series left with zero chunks.

## Cleanup

In addition to the `cleanup/1` function, the coordinator schedules cleanup periodically with `Process.send_after` based on `:cleanup_interval_ms` and applies the same rule across all shards. The timer message is the bare atom `:cleanup_tick`, handled by the coordinator in `handle_info/2`: it runs one cleanup pass across all shards and schedules the next tick. Sending `:cleanup_tick` to the coordinator directly must therefore trigger exactly one cleanup pass (a tick that finds nothing expired deletes nothing and must not crash the coordinator).

## Constraints

- Use only OTP standard library — no external dependencies.
- Give me the complete module in a single file.
- No ETS — all storage lives in the shard processes' GenServer state.
