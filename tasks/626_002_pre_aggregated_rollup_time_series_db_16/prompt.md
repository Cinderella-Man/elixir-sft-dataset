# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `start_link` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir GenServer module called `RollupTSDB` that implements a time-series storage engine that **pre-aggregates data on ingest** instead of keeping raw samples. Rather than storing every data point, each series keeps one compact *rollup accumulator* per fixed-width time bucket, so memory use per bucket is constant no matter how many points land in it.

## Public API

- `RollupTSDB.start_link(opts)` to start the process, returning `{:ok, pid}`. It should accept:
  - `:bucket_duration_ms` — the width of each rollup bucket in milliseconds (default `60_000`, i.e. one minute). Every unique series (metric name + exact label set) gets one rollup accumulator per time bucket.
  - `:clock` — a zero-arity function returning the current time in milliseconds. Default to `fn -> System.monotonic_time(:millisecond) end`. The clock is consulted **only when a cleanup run happens** — never during `init`, `insert`, or `query`.
  - `:name` — optional process registration name. When omitted, the process is started unregistered.
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
  - `stats` is a map with exactly these keys and no others:
    - `:count`, `:sum`, `:min`, `:max` — as accumulated above.
    - `:avg` — `sum / count` (always a float).
    - `:first`, `:last` — as accumulated above.
  - A series that matches but which has NO bucket in the `[start_ts, end_ts]` range must be omitted from the result entirely — never returned as a `{labels, []}` tuple. When no matched series has any bucket in range (including when the metric name is unknown), the result is `[]`.

## Cleanup

Handle a `:cleanup` info message that removes any bucket whose `bucket_start + bucket_duration_ms` is less than or equal to `now - retention_ms` (where `now` comes from `:clock`). A series left with zero buckets after cleanup is removed entirely. This message may also be sent directly to the process (`send(db, :cleanup)`) to force a cleanup run; any other info message must be ignored without crashing.

Also schedule this periodically using `Process.send_after`: arm the first timer during `init` using `:cleanup_interval_ms`, and re-arm it after each `:cleanup` run so automatic cleanup keeps repeating. When `:cleanup_interval_ms` is `:infinity`, no timer is armed at all and no automatic cleanup ever runs.

## Constraints

- Use only OTP standard library — no external dependencies.
- Give me the complete module in a single file.
- All operations go through the GenServer (`call`/`cast`) — no ETS, no separate processes.

## The module with `start_link` missing

```elixir
defmodule RollupTSDB do
  @moduledoc """
  A time-series storage engine that pre-aggregates data on ingest.

  Instead of retaining every raw sample, `RollupTSDB` keeps one compact
  *rollup accumulator* per fixed-width time bucket for each unique series
  (metric name + exact label set). Because each bucket stores only a small,
  constant-size accumulator (`count`, `sum`, `min`, `max`, `first`, `last`),
  memory use per bucket is constant regardless of how many points land in it.

  All state lives inside a single GenServer; there is no ETS and there are no
  helper processes. Expired buckets are removed periodically (and on demand)
  based on the configured retention window.
  """

  use GenServer

  @type metric_name :: String.t()
  @type labels :: %{optional(String.t()) => String.t()}
  @type bucket_start :: integer()

  @type stats :: %{
          count: non_neg_integer(),
          sum: number(),
          min: number(),
          max: number(),
          avg: float(),
          first: number(),
          last: number()
        }

  @default_bucket_duration_ms 60_000
  @default_retention_ms 3_600_000
  @default_cleanup_interval_ms 60_000

  # Internal accumulator kept per bucket. `first_ts`/`last_ts` track the
  # smallest/largest timestamps folded in, to resolve `first`/`last` ties.
  @typep acc :: %{
           count: non_neg_integer(),
           sum: number(),
           min: number(),
           max: number(),
           first: number(),
           last: number(),
           first_ts: integer(),
           last_ts: integer()
         }

  ## Public API

  def start_link(opts) do
    # TODO
  end

  @doc """
  Folds a single data point into the appropriate rollup bucket.

  The point is attributed to the bucket identified by
  `div(timestamp, bucket_duration_ms) * bucket_duration_ms` for the series
  `{metric_name, Enum.sort(Map.to_list(labels))}`. No raw point is stored;
  only the bucket's accumulator is updated. Always returns `:ok`.
  """
  @spec insert(GenServer.server(), metric_name(), labels(), integer(), number()) :: :ok
  def insert(server, metric_name, labels, timestamp, value) do
    GenServer.cast(server, {:insert, metric_name, labels, timestamp, value})
  end

  @doc """
  Queries rollup buckets for series matching `metric_name` and `label_matchers`.

  A series matches when it contains **all** key/value pairs in
  `label_matchers` (extra labels are allowed); an empty map matches every
  series with the given metric name. Returns a list of `{labels, buckets}`
  tuples where `buckets` is a list of `{bucket_start, stats}` sorted ascending
  by `bucket_start`, restricted to `start_ts <= bucket_start <= end_ts`.

  Series with no bucket in range are omitted entirely.
  """
  @spec query(
          GenServer.server(),
          metric_name(),
          labels(),
          {integer(), integer()}
        ) :: [{labels(), [{bucket_start(), stats()}]}]
  def query(server, metric_name, label_matchers, {start_ts, end_ts}) do
    GenServer.call(server, {:query, metric_name, label_matchers, start_ts, end_ts})
  end

  ## GenServer callbacks

  @impl true
  @spec init(keyword()) :: {:ok, map()}
  def init(opts) do
    bucket_duration_ms = Keyword.get(opts, :bucket_duration_ms, @default_bucket_duration_ms)
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    retention_ms = Keyword.get(opts, :retention_ms, @default_retention_ms)
    cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)

    state = %{
      bucket_duration_ms: bucket_duration_ms,
      clock: clock,
      retention_ms: retention_ms,
      cleanup_interval_ms: cleanup_interval_ms,
      series: %{}
    }

    schedule_cleanup(cleanup_interval_ms)
    {:ok, state}
  end

  @impl true
  def handle_cast({:insert, metric_name, labels, timestamp, value}, state) do
    key = series_key(metric_name, labels)
    bucket_start = div(timestamp, state.bucket_duration_ms) * state.bucket_duration_ms

    entry = Map.get(state.series, key, %{labels: labels, buckets: %{}})
    acc = Map.get(entry.buckets, bucket_start)
    new_acc = fold(acc, timestamp, value)

    new_buckets = Map.put(entry.buckets, bucket_start, new_acc)
    new_entry = %{entry | buckets: new_buckets}
    {:noreply, %{state | series: Map.put(state.series, key, new_entry)}}
  end

  @impl true
  def handle_call({:query, metric_name, label_matchers, start_ts, end_ts}, _from, state) do
    result =
      state.series
      |> Enum.filter(fn {{name, _sorted}, entry} ->
        name == metric_name and matches?(entry.labels, label_matchers)
      end)
      |> Enum.map(fn {_key, entry} ->
        {entry.labels, buckets_in_range(entry.buckets, start_ts, end_ts)}
      end)
      |> Enum.reject(fn {_labels, buckets} -> buckets == [] end)

    {:reply, result, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = state.clock.()
    cutoff = now - state.retention_ms

    new_series =
      state.series
      |> Enum.reduce(%{}, fn {key, entry}, acc ->
        kept = drop_expired_buckets(entry.buckets, cutoff, state.bucket_duration_ms)

        if map_size(kept) == 0 do
          acc
        else
          Map.put(acc, key, %{entry | buckets: kept})
        end
      end)

    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, %{state | series: new_series}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Internal helpers

  @spec series_key(metric_name(), labels()) :: {metric_name(), [{String.t(), String.t()}]}
  defp series_key(metric_name, labels) do
    {metric_name, Enum.sort(Map.to_list(labels))}
  end

  @spec fold(acc() | nil, integer(), number()) :: acc()
  defp fold(nil, timestamp, value) do
    %{
      count: 1,
      sum: value,
      min: value,
      max: value,
      first: value,
      last: value,
      first_ts: timestamp,
      last_ts: timestamp
    }
  end

  defp fold(acc, timestamp, value) do
    {first, first_ts} =
      if timestamp < acc.first_ts do
        {value, timestamp}
      else
        {acc.first, acc.first_ts}
      end

    {last, last_ts} =
      if timestamp >= acc.last_ts do
        {value, timestamp}
      else
        {acc.last, acc.last_ts}
      end

    %{
      count: acc.count + 1,
      sum: acc.sum + value,
      min: min(acc.min, value),
      max: max(acc.max, value),
      first: first,
      last: last,
      first_ts: first_ts,
      last_ts: last_ts
    }
  end

  @spec matches?(labels(), labels()) :: boolean()
  defp matches?(labels, label_matchers) do
    Enum.all?(label_matchers, fn {k, v} -> Map.get(labels, k) == v end)
  end

  @spec buckets_in_range(%{bucket_start() => acc()}, integer(), integer()) ::
          [{bucket_start(), stats()}]
  defp buckets_in_range(buckets, start_ts, end_ts) do
    buckets
    |> Enum.filter(fn {bucket_start, _acc} ->
      start_ts <= bucket_start and bucket_start <= end_ts
    end)
    |> Enum.sort_by(fn {bucket_start, _acc} -> bucket_start end)
    |> Enum.map(fn {bucket_start, acc} -> {bucket_start, to_stats(acc)} end)
  end

  @spec to_stats(acc()) :: stats()
  defp to_stats(acc) do
    %{
      count: acc.count,
      sum: acc.sum,
      min: acc.min,
      max: acc.max,
      avg: acc.sum / acc.count,
      first: acc.first,
      last: acc.last
    }
  end

  @spec drop_expired_buckets(%{bucket_start() => acc()}, integer(), pos_integer()) ::
          %{bucket_start() => acc()}
  defp drop_expired_buckets(buckets, cutoff, bucket_duration_ms) do
    buckets
    |> Enum.reject(fn {bucket_start, _acc} ->
      bucket_start + bucket_duration_ms <= cutoff
    end)
    |> Map.new()
  end

  @spec schedule_cleanup(non_neg_integer() | :infinity) :: :ok
  defp schedule_cleanup(:infinity), do: :ok

  defp schedule_cleanup(interval) do
    Process.send_after(self(), :cleanup, interval)
    :ok
  end
end
```

Give me only the complete implementation of `start_link` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
