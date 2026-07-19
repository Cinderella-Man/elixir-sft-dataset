# Write the missing @spec

Below is a complete, working module — except that the `@spec` for
`drop_expired_buckets/3` has been removed; its place is marked `# TODO: @spec`.
Write exactly that typespec: one `@spec` attribute for `drop_expired_buckets/3`,
consistent with the function's arguments, guards, and every return shape
the implementation can produce. Change nothing else.

## The module with the `@spec` for `drop_expired_buckets/3` missing

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

  @doc """
  Starts the `RollupTSDB` server.

  Options:

    * `:bucket_duration_ms` - width of each rollup bucket in milliseconds
      (default `#{@default_bucket_duration_ms}`).
    * `:clock` - zero-arity function returning the current time in
      milliseconds (default `System.monotonic_time/1` in `:millisecond`).
    * `:name` - optional process registration name.
    * `:retention_ms` - how long buckets are kept before becoming eligible for
      cleanup (default `#{@default_retention_ms}`).
    * `:cleanup_interval_ms` - how often automatic cleanup runs, or `:infinity`
      to disable it (default `#{@default_cleanup_interval_ms}`).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    case name do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
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

  # TODO: @spec
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

Give me only the `@spec` attribute — the attribute alone (however many
lines it spans), not the whole module.
