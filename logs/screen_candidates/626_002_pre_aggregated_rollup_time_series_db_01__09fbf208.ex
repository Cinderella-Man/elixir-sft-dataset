defmodule RollupTSDB do
  @moduledoc """
  A time-series storage engine that pre-aggregates data on ingest.

  Instead of retaining every raw sample, `RollupTSDB` folds each incoming point into a
  compact *rollup accumulator* held per series, per fixed-width time bucket. Memory used by
  a bucket is therefore constant regardless of how many points land inside it.

  A series is identified by the tuple `{metric_name, sorted_labels}` where `sorted_labels`
  is `Enum.sort(Map.to_list(labels))`, so the ordering of keys in the caller's label map can
  never produce duplicate series.

  Each bucket accumulator tracks `count`, `sum`, `min`, `max`, `first` (value at the smallest
  timestamp folded in) and `last` (value at the largest timestamp folded in). Queries derive
  `avg` from `sum / count` on read.

  Buckets older than the configured retention window are dropped by a periodic `:cleanup`
  pass, and any series left without buckets is removed entirely.

  ## Example

      {:ok, db} = RollupTSDB.start_link(bucket_duration_ms: 60_000)
      :ok = RollupTSDB.insert(db, "http_requests_total", %{"method" => "GET"}, 1_000, 5)
      :ok = RollupTSDB.insert(db, "http_requests_total", %{"method" => "GET"}, 2_000, 7)
      RollupTSDB.query(db, "http_requests_total", %{}, {0, 60_000})
      #=> [{%{"method" => "GET"},
      #=>   [{0, %{count: 2, sum: 12, min: 5, max: 7, avg: 6.0, first: 5, last: 7}}]}]
  """

  use GenServer

  @default_bucket_duration_ms 60_000
  @default_retention_ms 3_600_000
  @default_cleanup_interval_ms 60_000

  @typedoc "A metric name, e.g. `\"http_requests_total\"`."
  @type metric_name :: String.t()

  @typedoc "A label set, e.g. `%{\"method\" => \"GET\"}`."
  @type labels :: %{optional(String.t()) => String.t()}

  @typedoc "Milliseconds since some epoch (or a monotonic reading)."
  @type timestamp :: integer()

  @typedoc "The internal, in-place rollup accumulator for a single bucket."
  @type acc :: %{
          count: non_neg_integer(),
          sum: number(),
          min: number(),
          max: number(),
          first: number(),
          last: number(),
          first_ts: timestamp(),
          last_ts: timestamp()
        }

  @typedoc "The statistics returned for a bucket by `query/4`."
  @type stats :: %{
          count: non_neg_integer(),
          sum: number(),
          min: number(),
          max: number(),
          avg: float(),
          first: number(),
          last: number()
        }

  @typedoc "A series key: the metric name plus its labels as a sorted keyword-ish list."
  @type series_key :: {metric_name(), [{String.t(), String.t()}]}

  @typedoc "Options accepted by `start_link/1`."
  @type option ::
          {:bucket_duration_ms, pos_integer()}
          | {:retention_ms, non_neg_integer()}
          | {:cleanup_interval_ms, pos_integer() | :infinity}
          | {:clock, (-> timestamp())}
          | {:name, GenServer.name()}

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the rollup store.

  ## Options

    * `:bucket_duration_ms` — width of each rollup bucket, in milliseconds
      (default `#{@default_bucket_duration_ms}`).
    * `:retention_ms` — how long a bucket is kept before it becomes eligible for cleanup
      (default `#{@default_retention_ms}`).
    * `:cleanup_interval_ms` — how often the periodic cleanup runs, or `:infinity` to
      disable it (default `#{@default_cleanup_interval_ms}`).
    * `:clock` — zero-arity function returning "now" in milliseconds
      (default `fn -> System.monotonic_time(:millisecond) end`).
    * `:name` — optional registration name for the process.
  """
  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Folds a single data point into the rollup accumulator for its series and bucket.

  No raw sample is retained: the point updates `count`, `sum`, `min`, `max`, `first` and
  `last` in place. The bucket is chosen as
  `div(timestamp, bucket_duration_ms) * bucket_duration_ms`.

  Always returns `:ok`.
  """
  @spec insert(GenServer.server(), metric_name(), labels(), timestamp(), number()) :: :ok
  def insert(server, metric_name, labels, timestamp, value)
      when is_binary(metric_name) and is_map(labels) and is_integer(timestamp) and
             is_number(value) do
    GenServer.call(server, {:insert, metric_name, labels, timestamp, value})
  end

  @doc """
  Queries pre-aggregated buckets for every series matching `metric_name` and `label_matchers`.

  A series matches when its label map contains **all** key-value pairs given in
  `label_matchers`; extra labels are allowed. An empty matcher map matches every series
  carrying that metric name.

  Returns a list of `{labels, buckets}` tuples where `buckets` is a list of
  `{bucket_start, stats}` sorted ascending by `bucket_start` and restricted to buckets with
  `start_ts <= bucket_start <= end_ts`. Series with no bucket in range are omitted, so an
  empty overall result is `[]`.
  """
  @spec query(
          GenServer.server(),
          metric_name(),
          labels(),
          {timestamp(), timestamp()}
        ) :: [{labels(), [{timestamp(), stats()}]}]
  def query(server, metric_name, label_matchers, {start_ts, end_ts})
      when is_binary(metric_name) and is_map(label_matchers) and is_integer(start_ts) and
             is_integer(end_ts) do
    GenServer.call(server, {:query, metric_name, label_matchers, start_ts, end_ts})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    state = %{
      bucket_duration_ms: Keyword.get(opts, :bucket_duration_ms, @default_bucket_duration_ms),
      retention_ms: Keyword.get(opts, :retention_ms, @default_retention_ms),
      cleanup_interval_ms: Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms),
      clock: Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end),
      # %{series_key => %{bucket_start => acc}}
      series: %{}
    }

    schedule_cleanup(state)
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:insert, metric_name, labels, timestamp, value}, _from, state) do
    key = series_key(metric_name, labels)
    bucket_start = bucket_start(timestamp, state.bucket_duration_ms)

    buckets = Map.get(state.series, key, %{})
    acc = fold(Map.get(buckets, bucket_start), timestamp, value)
    buckets = Map.put(buckets, bucket_start, acc)

    {:reply, :ok, %{state | series: Map.put(state.series, key, buckets)}}
  end

  def handle_call({:query, metric_name, matchers, start_ts, end_ts}, _from, state) do
    matcher_list = Map.to_list(matchers)

    result =
      state.series
      |> Enum.filter(fn {{name, sorted_labels}, _buckets} ->
        name == metric_name and matches?(sorted_labels, matcher_list)
      end)
      |> Enum.reduce([], fn {{_name, sorted_labels}, buckets}, out ->
        case buckets_in_range(buckets, start_ts, end_ts) do
          [] -> out
          in_range -> [{Map.new(sorted_labels), in_range} | out]
        end
      end)
      |> Enum.reverse()

    {:reply, result, state}
  end

  @impl GenServer
  def handle_info(:cleanup, state) do
    cutoff = state.clock.() - state.retention_ms

    series =
      state.series
      |> Enum.reduce(%{}, fn {key, buckets}, acc ->
        kept =
          Map.reject(buckets, fn {bucket_start, _bucket_acc} ->
            bucket_start + state.bucket_duration_ms <= cutoff
          end)

        if map_size(kept) == 0, do: acc, else: Map.put(acc, key, kept)
      end)

    state = %{state | series: series}
    schedule_cleanup(state)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  @spec schedule_cleanup(map()) :: :ok
  defp schedule_cleanup(%{cleanup_interval_ms: :infinity}), do: :ok

  defp schedule_cleanup(%{cleanup_interval_ms: interval}) when is_integer(interval) do
    Process.send_after(self(), :cleanup, interval)
    :ok
  end

  @spec series_key(metric_name(), labels()) :: series_key()
  defp series_key(metric_name, labels), do: {metric_name, Enum.sort(Map.to_list(labels))}

  @spec bucket_start(timestamp(), pos_integer()) :: timestamp()
  defp bucket_start(timestamp, bucket_duration_ms) do
    div(timestamp, bucket_duration_ms) * bucket_duration_ms
  end

  # Seed the accumulator with the first point to land in the bucket.
  @spec fold(acc() | nil, timestamp(), number()) :: acc()
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

  @spec matches?([{String.t(), String.t()}], [{String.t(), String.t()}]) :: boolean()
  defp matches?(sorted_labels, matcher_list) do
    Enum.all?(matcher_list, fn pair -> pair in sorted_labels end)
  end

  @spec buckets_in_range(%{optional(timestamp()) => acc()}, timestamp(), timestamp()) ::
          [{timestamp(), stats()}]
  defp buckets_in_range(buckets, start_ts, end_ts) do
    buckets
    |> Enum.filter(fn {bucket_start, _acc} ->
      bucket_start >= start_ts and bucket_start <= end_ts
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
end