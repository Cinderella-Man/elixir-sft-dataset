defmodule CounterTSDB do
  @moduledoc """
  A time-series storage engine for **monotonic counters**, implemented as a `GenServer`.

  Counters are metrics that normally only increase (for example `http_requests_total`).
  When a process exporting a counter restarts, the counter goes back toward zero. This
  module treats an observed drop between two consecutive samples as a *counter reset*
  rather than as a negative change, so range queries never report negative increases.

  ## Storage layout

  Every unique series — the pair of a metric name and an exact label set — is stored as a
  collection of chunks. A chunk covers a fixed time window of `:chunk_duration_ms`
  milliseconds, and the chunk holding a point with timestamp `ts` starts at
  `div(ts, chunk_duration_ms) * chunk_duration_ms`. Data points inside a chunk are kept
  sorted by timestamp.

  Series identity is `{metric_name, Enum.sort(Map.to_list(labels))}`, so the order in which
  labels are written never produces duplicate series.

  ## Queries

  * `query/4` returns the raw `{timestamp, value}` samples of every matching series.
  * `query_range/6` divides the requested range into `step_ms`-wide windows and computes a
    reset-aware `:increase` or `:rate` for each window.

  ## Retention

  Chunks older than `:retention_ms` are dropped by a periodic `:cleanup` message scheduled
  with `Process.send_after/3`. Series left without any chunk are removed.

  All state lives in the `GenServer` — no ETS tables and no helper processes are used.
  """

  use GenServer

  @default_chunk_duration_ms 60_000
  @default_retention_ms 3_600_000
  @default_cleanup_interval_ms 60_000

  @typedoc "A metric name."
  @type metric_name :: String.t()

  @typedoc "A label set, e.g. `%{\"instance\" => \"a\"}`."
  @type labels :: %{optional(String.t()) => String.t()}

  @typedoc "A single sample: a millisecond timestamp and a numeric value."
  @type point :: {integer(), number()}

  @typedoc "Inclusive time range in milliseconds."
  @type range :: {integer(), integer()}

  @typedoc "Aggregation function supported by `query_range/6`."
  @type range_function :: :increase | :rate

  @typedoc "Internal series key: metric name plus sorted label pairs."
  @type series_key :: {metric_name(), [{String.t(), String.t()}]}

  defmodule State do
    @moduledoc false

    defstruct chunk_duration_ms: 60_000,
              retention_ms: 3_600_000,
              cleanup_interval_ms: 60_000,
              clock: nil,
              series: %{}

    @type t :: %__MODULE__{
            chunk_duration_ms: pos_integer(),
            retention_ms: non_neg_integer(),
            cleanup_interval_ms: pos_integer() | :infinity,
            clock: (-> integer()),
            series: %{
              optional(CounterTSDB.series_key()) => %{
                labels: CounterTSDB.labels(),
                chunks: %{optional(integer()) => [CounterTSDB.point()]}
              }
            }
          }
  end

  # ----------------------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------------------

  @doc """
  Starts the counter store.

  ## Options

    * `:chunk_duration_ms` — width of each storage chunk in milliseconds
      (default `#{@default_chunk_duration_ms}`).
    * `:retention_ms` — how long a chunk is kept before it becomes eligible for cleanup
      (default `#{@default_retention_ms}`).
    * `:cleanup_interval_ms` — how often automatic cleanup runs, or `:infinity` to disable
      it (default `#{@default_cleanup_interval_ms}`).
    * `:clock` — zero-arity function returning "now" in milliseconds. Defaults to
      `fn -> System.monotonic_time(:millisecond) end`.
    * `:name` — optional name to register the process under.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Inserts a single counter sample.

  The point is routed to the chunk starting at
  `div(timestamp, chunk_duration_ms) * chunk_duration_ms` and kept in timestamp order
  within that chunk. Always returns `:ok`.
  """
  @spec insert(GenServer.server(), metric_name(), labels(), integer(), number()) :: :ok
  def insert(server, metric_name, labels, timestamp, value)
      when is_binary(metric_name) and is_map(labels) and is_integer(timestamp) and
             is_number(value) do
    GenServer.cast(server, {:insert, metric_name, labels, timestamp, value})
  end

  @doc """
  Returns the raw samples of every series matching `metric_name` and `label_matchers`.

  A series matches when it contains all key-value pairs of `label_matchers`; extra labels
  are allowed, and `%{}` matches every series carrying the metric name.

  The result is a list of `{labels, points}` tuples where `points` holds the
  `{timestamp, value}` samples with `start_ts <= timestamp <= end_ts`, sorted ascending.
  Matching series without any point in the range are omitted.
  """
  @spec query(GenServer.server(), metric_name(), labels(), range()) :: [{labels(), [point()]}]
  def query(server, metric_name, label_matchers, {start_ts, end_ts})
      when is_binary(metric_name) and is_map(label_matchers) and is_integer(start_ts) and
             is_integer(end_ts) do
    GenServer.call(server, {:query, metric_name, label_matchers, {start_ts, end_ts}})
  end

  @doc """
  Computes a reset-aware aggregation over fixed-width windows.

  The half-open range `[start_ts, end_ts)` is split into consecutive windows of `step_ms`
  milliseconds. For each matching series and each window, the points falling into
  `[window_start, window_start + step_ms)` are aggregated with `function`:

    * `:increase` — sum of the deltas between consecutive samples, where a delta is
      `cur - prev` when `cur >= prev` and `cur` otherwise (a reset: the counter is treated
      as having climbed from zero to `cur`).
    * `:rate` — the same reset-aware increase divided by the elapsed seconds between the
      first and the last timestamp of the window.

  Windows with fewer than two points are omitted, as are `:rate` windows whose first and
  last timestamps coincide. Series left without any window are omitted from the result.

  Returns a list of `{labels, [{window_start, value}]}` tuples ordered by window start.
  """
  @spec query_range(
          GenServer.server(),
          metric_name(),
          labels(),
          range(),
          range_function(),
          pos_integer()
        ) :: [{labels(), [{integer(), number()}]}]
  def query_range(server, metric_name, label_matchers, {start_ts, end_ts}, function, step_ms)
      when is_binary(metric_name) and is_map(label_matchers) and is_integer(start_ts) and
             is_integer(end_ts) and function in [:increase, :rate] and is_integer(step_ms) and
             step_ms > 0 do
    request =
      {:query_range, metric_name, label_matchers, {start_ts, end_ts}, function, step_ms}

    GenServer.call(server, request)
  end

  # ----------------------------------------------------------------------------
  # GenServer callbacks
  # ----------------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    state = %State{
      chunk_duration_ms: Keyword.get(opts, :chunk_duration_ms, @default_chunk_duration_ms),
      retention_ms: Keyword.get(opts, :retention_ms, @default_retention_ms),
      cleanup_interval_ms:
        Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms),
      clock: Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end),
      series: %{}
    }

    schedule_cleanup(state)
    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:insert, metric_name, labels, timestamp, value}, state) do
    key = series_key(metric_name, labels)
    chunk_start = div(timestamp, state.chunk_duration_ms) * state.chunk_duration_ms

    entry = Map.get(state.series, key, %{labels: labels, chunks: %{}})
    points = Map.get(entry.chunks, chunk_start, [])
    chunks = Map.put(entry.chunks, chunk_start, insert_sorted(points, {timestamp, value}))
    series = Map.put(state.series, key, %{entry | chunks: chunks})

    {:noreply, %{state | series: series}}
  end

  @impl GenServer
  def handle_call({:query, metric_name, label_matchers, {start_ts, end_ts}}, _from, state) do
    result =
      state
      |> matching_series(metric_name, label_matchers)
      |> Enum.map(fn {labels, points} ->
        {labels, Enum.filter(points, fn {ts, _v} -> ts >= start_ts and ts <= end_ts end)}
      end)
      |> Enum.reject(fn {_labels, points} -> points == [] end)

    {:reply, result, state}
  end

  def handle_call(
        {:query_range, metric_name, label_matchers, {start_ts, end_ts}, function, step_ms},
        _from,
        state
      ) do
    windows = windows(start_ts, end_ts, step_ms)

    result =
      state
      |> matching_series(metric_name, label_matchers)
      |> Enum.map(fn {labels, points} ->
        {labels, range_points(points, windows, step_ms, function)}
      end)
      |> Enum.reject(fn {_labels, range_points} -> range_points == [] end)

    {:reply, result, state}
  end

  @impl GenServer
  def handle_info(:cleanup, state) do
    state = cleanup(state)
    schedule_cleanup(state)
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  # ----------------------------------------------------------------------------
  # Internal helpers
  # ----------------------------------------------------------------------------

  @spec series_key(metric_name(), labels()) :: series_key()
  defp series_key(metric_name, labels), do: {metric_name, Enum.sort(Map.to_list(labels))}

  @spec insert_sorted([point()], point()) :: [point()]
  defp insert_sorted([], point), do: [point]

  defp insert_sorted([{head_ts, _} = head | rest], {ts, _} = point) when ts < head_ts do
    [point, head | rest]
  end

  defp insert_sorted([head | rest], point), do: [head | insert_sorted(rest, point)]

  @spec matching_series(State.t(), metric_name(), labels()) :: [{labels(), [point()]}]
  defp matching_series(state, metric_name, label_matchers) do
    state.series
    |> Enum.filter(fn {{name, _sorted}, entry} ->
      name == metric_name and matches?(entry.labels, label_matchers)
    end)
    |> Enum.map(fn {_key, entry} -> {entry.labels, all_points(entry.chunks)} end)
  end

  @spec matches?(labels(), labels()) :: boolean()
  defp matches?(labels, label_matchers) do
    Enum.all?(label_matchers, fn {k, v} -> Map.get(labels, k) == v end)
  end

  @spec all_points(%{optional(integer()) => [point()]}) :: [point()]
  defp all_points(chunks) do
    chunks
    |> Enum.sort_by(fn {chunk_start, _points} -> chunk_start end)
    |> Enum.flat_map(fn {_chunk_start, points} -> points end)
  end

  @spec windows(integer(), integer(), pos_integer()) :: [integer()]
  defp windows(start_ts, end_ts, step_ms) when start_ts >= end_ts, do: []

  defp windows(start_ts, end_ts, step_ms) do
    Stream.iterate(start_ts, &(&1 + step_ms))
    |> Enum.take_while(fn window_start -> window_start < end_ts end)
  end

  @spec range_points([point()], [integer()], pos_integer(), range_function()) ::
          [{integer(), number()}]
  defp range_points(points, windows, step_ms, function) do
    Enum.flat_map(windows, fn window_start ->
      window_points =
        Enum.filter(points, fn {ts, _v} ->
          ts >= window_start and ts < window_start + step_ms
        end)

      case compute(window_points, function) do
        {:ok, value} -> [{window_start, value}]
        :none -> []
      end
    end)
  end

  @spec compute([point()], range_function()) :: {:ok, number()} | :none
  defp compute(points, _function) when length(points) < 2, do: :none

  defp compute(points, :increase), do: {:ok, reset_aware_increase(points)}

  defp compute(points, :rate) do
    {first_ts, _} = List.first(points)
    {last_ts, _} = List.last(points)

    if last_ts == first_ts do
      :none
    else
      seconds = (last_ts - first_ts) / 1000
      {:ok, reset_aware_increase(points) / seconds}
    end
  end

  @spec reset_aware_increase([point()]) :: number()
  defp reset_aware_increase(points) do
    points
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce(0, fn [{_prev_ts, prev_value}, {_cur_ts, cur_value}], acc ->
      if cur_value >= prev_value do
        acc + (cur_value - prev_value)
      else
        acc + cur_value
      end
    end)
  end

  @spec cleanup(State.t()) :: State.t()
  defp cleanup(state) do
    now = state.clock.()
    cutoff = now - state.retention_ms

    series =
      state.series
      |> Enum.reduce(%{}, fn {key, entry}, acc ->
        chunks =
          entry.chunks
          |> Enum.reject(fn {chunk_start, _points} ->
            chunk_start + state.chunk_duration_ms <= cutoff
          end)
          |> Map.new()

        if map_size(chunks) == 0 do
          acc
        else
          Map.put(acc, key, %{entry | chunks: chunks})
        end
      end)

    %{state | series: series}
  end

  @spec schedule_cleanup(State.t()) :: :ok
  defp schedule_cleanup(%State{cleanup_interval_ms: :infinity}), do: :ok

  defp schedule_cleanup(%State{cleanup_interval_ms: interval}) do
    Process.send_after(self(), :cleanup, interval)
    :ok
  end
end