# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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
  @spec start_link(keyword()) :: GenServer.on_start()
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

## Test harness — implement the `# TODO` test

```elixir
defmodule CounterTSDBTest do
  use ExUnit.Case, async: false

  defmodule Clock do
    use Agent

    def start_link(initial \\ 0) do
      Agent.start_link(fn -> initial end, name: __MODULE__)
    end

    def now, do: Agent.get(__MODULE__, & &1)
    def set(ms), do: Agent.update(__MODULE__, fn _ -> ms end)
  end

  setup do
    start_supervised!({Clock, 0})

    {:ok, pid} =
      CounterTSDB.start_link(
        clock: &Clock.now/0,
        chunk_duration_ms: 1_000,
        retention_ms: 10_000,
        cleanup_interval_ms: :infinity
      )

    %{db: pid}
  end

  # -------------------------------------------------------
  # Raw query
  # -------------------------------------------------------

  test "insert and query returns sorted points within inclusive range", %{db: db} do
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "a"}, 300, 30)
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "a"}, 100, 10)
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "a"}, 200, 20)

    [{%{"i" => "a"}, points}] = CounterTSDB.query(db, "reqs", %{"i" => "a"}, {0, 500})
    assert points == [{100, 10}, {200, 20}, {300, 30}]
  end

  test "query omits series with no points in range", %{db: db} do
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "a"}, 100, 10)
    assert [] = CounterTSDB.query(db, "reqs", %{"i" => "a"}, {500, 600})
  end

  # -------------------------------------------------------
  # :increase (reset-aware)
  # -------------------------------------------------------

  test "increase over a monotonic window is the difference", %{db: db} do
    :ok = CounterTSDB.insert(db, "reqs", %{}, 0, 100)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 500, 160)

    [{_labels, range}] = CounterTSDB.query_range(db, "reqs", %{}, {0, 1000}, :increase, 1_000)
    assert range == [{0, 60}]
  end

  test "increase treats a mid-window drop as a counter reset", %{db: db} do
    # TODO
  end

  test "increase omits windows with fewer than 2 points", %{db: db} do
    # window [0,1000): only 1 point -> omitted
    :ok = CounterTSDB.insert(db, "reqs", %{}, 100, 42)
    # window [1000,2000): 2 points -> increase 50
    :ok = CounterTSDB.insert(db, "reqs", %{}, 1100, 10)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 1600, 60)

    [{_labels, range}] = CounterTSDB.query_range(db, "reqs", %{}, {0, 2000}, :increase, 1_000)
    assert range == [{1000, 50}]
  end

  test "increase buckets points into separate windows", %{db: db} do
    :ok = CounterTSDB.insert(db, "reqs", %{}, 0, 10)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 100, 20)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 1000, 100)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 1500, 130)

    [{_labels, range}] = CounterTSDB.query_range(db, "reqs", %{}, {0, 2000}, :increase, 1_000)
    assert range == [{0, 10}, {1000, 30}]
  end

  # -------------------------------------------------------
  # :rate (reset-aware)
  # -------------------------------------------------------

  test "rate is per-second reset-aware increase", %{db: db} do
    # increase = 60; elapsed = (500-0)/1000 = 0.5s; rate = 120.0
    :ok = CounterTSDB.insert(db, "reqs", %{}, 0, 100)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 500, 160)

    [{_labels, [{0, rate}]}] = CounterTSDB.query_range(db, "reqs", %{}, {0, 1000}, :rate, 1_000)
    assert_in_delta rate, 120.0, 0.01
  end

  test "rate accounts for a reset within the window", %{db: db} do
    # values 10,15,5,8 at 0,100,200,300 -> increase 13; elapsed (300-0)/1000=0.3
    # rate = 13 / 0.3 = 43.333...
    :ok = CounterTSDB.insert(db, "reqs", %{}, 0, 10)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 100, 15)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 200, 5)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 300, 8)

    [{_labels, [{0, rate}]}] = CounterTSDB.query_range(db, "reqs", %{}, {0, 1000}, :rate, 1_000)
    assert_in_delta rate, 43.3333, 0.01
  end

  test "rate omits windows with fewer than 2 points", %{db: db} do
    :ok = CounterTSDB.insert(db, "reqs", %{}, 100, 5)
    assert [] = CounterTSDB.query_range(db, "reqs", %{}, {0, 1000}, :rate, 1_000)
  end

  test "rate omits a zero-elapsed window but keeps the other windows", %{db: db} do
    # window [0,1000): two points sharing timestamp 100 -> last == first -> omitted
    :ok = CounterTSDB.insert(db, "reqs", %{}, 100, 5)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 100, 9)
    # window [1000,2000): increase 50 over (1600-1100)/1000 = 0.5s -> 100.0
    :ok = CounterTSDB.insert(db, "reqs", %{}, 1100, 10)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 1600, 60)

    [{_labels, [{1000, rate}]}] =
      CounterTSDB.query_range(db, "reqs", %{}, {0, 2000}, :rate, 1_000)

    assert_in_delta rate, 100.0, 0.01
  end

  # -------------------------------------------------------
  # Duplicate timestamps are both retained
  # -------------------------------------------------------

  test "query returns both points inserted at the same timestamp", %{db: db} do
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "a"}, 100, 5)
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "a"}, 100, 9)
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "a"}, 200, 20)

    [{%{"i" => "a"}, points}] = CounterTSDB.query(db, "reqs", %{"i" => "a"}, {0, 500})

    # Both duplicate-timestamp samples survive, and the list stays sorted by
    # timestamp, so the pair at 100 precedes the point at 200.
    assert length(points) == 3
    assert Enum.map(points, fn {ts, _v} -> ts end) == [100, 100, 200]
    assert Enum.sort(points) == [{100, 5}, {100, 9}, {200, 20}]
  end

  test "increase counts a duplicate-timestamp pair as two points", %{db: db} do
    # Two samples share timestamp 100 and carry equal values, so whatever their
    # relative order the window holds 2 points and contributes a delta of 0.
    # A store that collapsed them would leave 1 point and omit the window.
    :ok = CounterTSDB.insert(db, "reqs", %{}, 100, 7)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 100, 7)

    [{_labels, range}] = CounterTSDB.query_range(db, "reqs", %{}, {0, 1000}, :increase, 1_000)
    assert range == [{0, 0}]
  end

  # -------------------------------------------------------
  # Label matching / multiple series
  # -------------------------------------------------------

  test "range query returns separate results per matched series", %{db: db} do
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "a"}, 0, 0)
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "a"}, 500, 10)
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "b"}, 0, 0)
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "b"}, 500, 40)

    result = CounterTSDB.query_range(db, "reqs", %{}, {0, 1000}, :increase, 1_000)
    assert length(result) == 2

    incs =
      result
      |> Enum.map(fn {labels, [{0, inc}]} -> {labels["i"], inc} end)
      |> Enum.sort()

    assert incs == [{"a", 10}, {"b", 40}]
  end

  test "label matchers select series containing all specified labels", %{db: db} do
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "a", "env" => "prod"}, 0, 0)
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "a", "env" => "prod"}, 500, 10)
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "b", "env" => "dev"}, 0, 0)
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "b", "env" => "dev"}, 500, 99)

    result = CounterTSDB.query_range(db, "reqs", %{"env" => "prod"}, {0, 1000}, :increase, 1_000)
    assert [{%{"env" => "prod"}, [{0, 10}]}] = result
  end

  test "label order does not create duplicate series", %{db: db} do
    :ok = CounterTSDB.insert(db, "reqs", %{"a" => "1", "b" => "2"}, 0, 0)
    :ok = CounterTSDB.insert(db, "reqs", %{"b" => "2", "a" => "1"}, 500, 20)

    [{_labels, [{0, inc}]}] =
      CounterTSDB.query_range(db, "reqs", %{"a" => "1", "b" => "2"}, {0, 1000}, :increase, 1_000)

    assert inc == 20
  end

  # -------------------------------------------------------
  # Cleanup
  # -------------------------------------------------------

  test "cleanup removes expired chunks", %{db: db} do
    :ok = CounterTSDB.insert(db, "reqs", %{}, 100, 1)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 5000, 2)

    Clock.set(12_000)
    send(db, :cleanup)

    # A subsequent public call is processed after :cleanup (FIFO mailbox),
    # so the query observes the post-cleanup state without touching internals.
    [{_labels, points}] = CounterTSDB.query(db, "reqs", %{}, {0, 20_000})
    assert points == [{5000, 2}]
  end

  test "cleanup removes a series with no remaining chunks", %{db: db} do
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "a"}, 100, 1)

    Clock.set(100_000)
    send(db, :cleanup)

    # The query below is handled after the :cleanup message, so it reflects
    # the cleaned-up state through the public API alone.
    assert [] = CounterTSDB.query(db, "reqs", %{"i" => "a"}, {0, 200_000})
  end

  test "cleanup runs on its own repeatedly on the cleanup interval" do
    test_pid = self()

    # The injected clock is only consulted by cleanup, so each read announces
    # that a cleanup pass ran without the test ever sending :cleanup itself.
    clock = fn ->
      send(test_pid, :cleanup_ran)
      1_000_000
    end

    {:ok, db} =
      CounterTSDB.start_link(
        clock: clock,
        chunk_duration_ms: 1_000,
        retention_ms: 10_000,
        cleanup_interval_ms: 25
      )

    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "a"}, 100, 1)

    # Two unsolicited passes: cleanup is scheduled again after it runs.
    assert_receive :cleanup_ran, 2_000
    assert_receive :cleanup_ran, 2_000

    # The chunk holding the point expired long before the clock's 1_000_000,
    # so the automatic pass dropped both the chunk and its now-empty series.
    assert [] = CounterTSDB.query(db, "reqs", %{"i" => "a"}, {0, 2_000_000})
  end

  test "increase treats an equal consecutive value as a zero delta, not a reset", %{db: db} do
    # values 10, 10, 15 -> deltas 0 (10 >= 10, no reset), 5 -> total 5
    :ok = CounterTSDB.insert(db, "reqs", %{}, 0, 10)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 100, 10)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 200, 15)

    [{_labels, range}] = CounterTSDB.query_range(db, "reqs", %{}, {0, 1000}, :increase, 1_000)
    assert range == [{0, 5}]
  end

  test "cleanup drops a chunk whose end exactly equals the retention threshold", %{db: db} do
    # chunk_duration_ms 1_000, retention_ms 10_000.
    :ok = CounterTSDB.insert(db, "reqs", %{}, 100, 1)
    :ok = CounterTSDB.insert(db, "reqs", %{}, 1_000, 2)

    # now - retention_ms = 1_000. Chunk 0 ends at 0 + 1_000 == 1_000 -> removed.
    # Chunk 1_000 ends at 2_000 > 1_000 -> kept.
    Clock.set(11_000)
    send(db, :cleanup)

    [{_labels, points}] = CounterTSDB.query(db, "reqs", %{}, {0, 20_000})
    assert points == [{1_000, 2}]
  end

  test "retention defaults to one hour when the option is omitted" do
    {:ok, db} =
      CounterTSDB.start_link(
        clock: &Clock.now/0,
        chunk_duration_ms: 1_000,
        cleanup_interval_ms: :infinity
      )

    :ok = CounterTSDB.insert(db, "reqs", %{}, 0, 1)

    # threshold = 100_000 - 3_600_000 < 0, so the chunk survives.
    Clock.set(100_000)
    send(db, :cleanup)
    [{_labels, points}] = CounterTSDB.query(db, "reqs", %{}, {0, 10_000})
    assert points == [{0, 1}]

    # threshold = 3_601_000 - 3_600_000 = 1_000; chunk ends at 1_000 -> expired.
    Clock.set(3_601_000)
    send(db, :cleanup)
    assert [] = CounterTSDB.query(db, "reqs", %{}, {0, 10_000})
  end

  test "chunk duration defaults to sixty seconds when the option is omitted" do
    {:ok, db} =
      CounterTSDB.start_link(
        clock: &Clock.now/0,
        retention_ms: 10_000,
        cleanup_interval_ms: :infinity
      )

    :ok = CounterTSDB.insert(db, "reqs", %{}, 0, 1)

    # threshold = 20_000 - 10_000 = 10_000; the default chunk ends at
    # 0 + 60_000 = 60_000 > 10_000, so the point must survive cleanup.
    Clock.set(20_000)
    send(db, :cleanup)

    [{_labels, points}] = CounterTSDB.query(db, "reqs", %{}, {0, 10_000})
    assert points == [{0, 1}]
  end

  test "the name option registers the process for public API calls" do
    {:ok, _pid} =
      CounterTSDB.start_link(
        name: :counter_tsdb_named_test,
        clock: &Clock.now/0,
        chunk_duration_ms: 1_000,
        cleanup_interval_ms: :infinity
      )

    :ok = CounterTSDB.insert(:counter_tsdb_named_test, "reqs", %{"i" => "a"}, 100, 5)
    :ok = CounterTSDB.insert(:counter_tsdb_named_test, "reqs", %{"i" => "a"}, 200, 9)

    assert [{%{"i" => "a"}, [{100, 5}, {200, 9}]}] =
             CounterTSDB.query(:counter_tsdb_named_test, "reqs", %{"i" => "a"}, {0, 500})
  end

  test "query returns an empty list when neither metric nor matchers select a series", %{db: db} do
    :ok = CounterTSDB.insert(db, "reqs", %{"i" => "a"}, 100, 10)

    assert [] == CounterTSDB.query(db, "other_metric", %{}, {0, 500})
    assert [] == CounterTSDB.query(db, "reqs", %{"i" => "z"}, {0, 500})
  end
end
```
