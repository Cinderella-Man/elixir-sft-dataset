# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule TSDBTest do
  use ExUnit.Case, async: false

  # --- Fake clock for deterministic testing ---

  defmodule Clock do
    use Agent

    def start_link(initial \\ 0) do
      Agent.start_link(fn -> initial end, name: __MODULE__)
    end

    def now, do: Agent.get(__MODULE__, & &1)
    def advance(ms), do: Agent.update(__MODULE__, &(&1 + ms))
    def set(ms), do: Agent.update(__MODULE__, fn _ -> ms end)
  end

  setup do
    start_supervised!({Clock, 0})

    {:ok, pid} =
      TSDB.start_link(
        clock: &Clock.now/0,
        chunk_duration_ms: 1_000,
        retention_ms: 10_000,
        cleanup_interval_ms: :infinity
      )

    %{db: pid}
  end

  # -------------------------------------------------------
  # Basic insert and query
  # -------------------------------------------------------

  test "insert and retrieve a single data point", %{db: db} do
    assert :ok = TSDB.insert(db, "cpu", %{"host" => "a"}, 100, 0.5)

    result = TSDB.query(db, "cpu", %{"host" => "a"}, {0, 200})
    assert [{%{"host" => "a"}, [{100, 0.5}]}] = result
  end

  test "multiple points in the same series are sorted by timestamp", %{db: db} do
    :ok = TSDB.insert(db, "cpu", %{"host" => "a"}, 300, 0.3)
    :ok = TSDB.insert(db, "cpu", %{"host" => "a"}, 100, 0.1)
    :ok = TSDB.insert(db, "cpu", %{"host" => "a"}, 200, 0.2)

    [{_labels, points}] = TSDB.query(db, "cpu", %{"host" => "a"}, {0, 500})
    assert points == [{100, 0.1}, {200, 0.2}, {300, 0.3}]
  end

  test "query filters by time range (inclusive bounds)", %{db: db} do
    for ts <- [100, 200, 300, 400, 500] do
      :ok = TSDB.insert(db, "m", %{}, ts, ts * 1.0)
    end

    [{_labels, points}] = TSDB.query(db, "m", %{}, {200, 400})
    timestamps = Enum.map(points, &elem(&1, 0))
    assert timestamps == [200, 300, 400]
  end

  test "query returns empty list when no data matches", %{db: db} do
    :ok = TSDB.insert(db, "m", %{"a" => "1"}, 100, 1)

    assert [] = TSDB.query(db, "m", %{"a" => "1"}, {500, 600})
    assert [] = TSDB.query(db, "other_metric", %{}, {0, 1000})
  end

  # -------------------------------------------------------
  # Label matching
  # -------------------------------------------------------

  test "label matchers select series that contain all specified labels", %{db: db} do
    :ok = TSDB.insert(db, "http", %{"method" => "GET", "status" => "200"}, 100, 1)
    :ok = TSDB.insert(db, "http", %{"method" => "POST", "status" => "200"}, 100, 2)
    :ok = TSDB.insert(db, "http", %{"method" => "GET", "status" => "500"}, 100, 3)

    # Match only status=200
    result = TSDB.query(db, "http", %{"status" => "200"}, {0, 200})
    assert length(result) == 2

    values =
      result |> Enum.flat_map(fn {_, pts} -> Enum.map(pts, &elem(&1, 1)) end) |> Enum.sort()

    assert values == [1, 2]
  end

  test "empty label matcher matches all series for that metric", %{db: db} do
    :ok = TSDB.insert(db, "http", %{"method" => "GET"}, 100, 1)
    :ok = TSDB.insert(db, "http", %{"method" => "POST"}, 100, 2)

    result = TSDB.query(db, "http", %{}, {0, 200})
    assert length(result) == 2
  end

  test "label order does not create duplicate series", %{db: db} do
    # These should go into the same series regardless of map key ordering
    :ok = TSDB.insert(db, "m", %{"a" => "1", "b" => "2"}, 100, 10)
    :ok = TSDB.insert(db, "m", %{"b" => "2", "a" => "1"}, 200, 20)

    result = TSDB.query(db, "m", %{"a" => "1", "b" => "2"}, {0, 300})
    assert length(result) == 1
    [{_labels, points}] = result
    assert points == [{100, 10}, {200, 20}]
  end

  # -------------------------------------------------------
  # Chunked storage
  # -------------------------------------------------------

  test "data points span multiple chunks correctly", %{db: db} do
    # chunk_duration_ms = 1_000, so chunk boundaries at 0, 1000, 2000 ...
    :ok = TSDB.insert(db, "m", %{}, 500, 1)
    :ok = TSDB.insert(db, "m", %{}, 1500, 2)
    :ok = TSDB.insert(db, "m", %{}, 2500, 3)

    [{_labels, points}] = TSDB.query(db, "m", %{}, {0, 3000})
    assert points == [{500, 1}, {1500, 2}, {2500, 3}]
  end

  test "querying a sub-range only returns points from relevant chunks", %{db: db} do
    # TODO
  end

  # -------------------------------------------------------
  # Aggregation: :sum
  # -------------------------------------------------------

  test "query_agg :sum computes the sum per window", %{db: db} do
    # Insert points: step_ms = 1000
    # Window [0, 1000): timestamps 100, 200, 300
    :ok = TSDB.insert(db, "m", %{}, 100, 10)
    :ok = TSDB.insert(db, "m", %{}, 200, 20)
    :ok = TSDB.insert(db, "m", %{}, 300, 30)
    # Window [1000, 2000): timestamps 1100, 1500
    :ok = TSDB.insert(db, "m", %{}, 1100, 5)
    :ok = TSDB.insert(db, "m", %{}, 1500, 15)

    [{_labels, agg_points}] = TSDB.query_agg(db, "m", %{}, {0, 2000}, :sum, 1_000)

    assert agg_points == [{0, 60}, {1000, 20}]
  end

  # -------------------------------------------------------
  # Aggregation: :avg
  # -------------------------------------------------------

  test "query_agg :avg computes the mean per window", %{db: db} do
    :ok = TSDB.insert(db, "m", %{}, 100, 10)
    :ok = TSDB.insert(db, "m", %{}, 200, 20)
    :ok = TSDB.insert(db, "m", %{}, 300, 30)

    [{_labels, agg_points}] = TSDB.query_agg(db, "m", %{}, {0, 1000}, :avg, 1_000)

    [{0, avg_value}] = agg_points
    assert_in_delta avg_value, 20.0, 0.01
  end

  # -------------------------------------------------------
  # Aggregation: :max
  # -------------------------------------------------------

  test "query_agg :max returns the maximum value per window", %{db: db} do
    :ok = TSDB.insert(db, "m", %{}, 100, 10)
    :ok = TSDB.insert(db, "m", %{}, 200, 50)
    :ok = TSDB.insert(db, "m", %{}, 300, 30)

    [{_labels, agg_points}] = TSDB.query_agg(db, "m", %{}, {0, 1000}, :max, 1_000)

    assert agg_points == [{0, 50}]
  end

  # -------------------------------------------------------
  # Aggregation: :rate
  # -------------------------------------------------------

  test "query_agg :rate computes per-second rate of change", %{db: db} do
    # Window [0, 1000): value goes from 100 at t=0 to 200 at t=500
    # rate = (200 - 100) / ((500 - 0) / 1000) = 100 / 0.5 = 200.0
    :ok = TSDB.insert(db, "m", %{}, 0, 100)
    :ok = TSDB.insert(db, "m", %{}, 500, 200)

    [{_labels, agg_points}] = TSDB.query_agg(db, "m", %{}, {0, 1000}, :rate, 1_000)

    [{0, rate}] = agg_points
    assert_in_delta rate, 200.0, 0.01
  end

  test "query_agg :rate omits windows with fewer than 2 points", %{db: db} do
    # Window [0, 1000): only 1 point — should be omitted
    :ok = TSDB.insert(db, "m", %{}, 100, 42)
    # Window [1000, 2000): 2 points — should be included
    :ok = TSDB.insert(db, "m", %{}, 1100, 10)
    :ok = TSDB.insert(db, "m", %{}, 1600, 60)

    [{_labels, agg_points}] = TSDB.query_agg(db, "m", %{}, {0, 2000}, :rate, 1_000)

    # Only the second window
    assert length(agg_points) == 1
    [{1000, rate}] = agg_points
    # (60 - 10) / ((1600 - 1100) / 1000) = 50 / 0.5 = 100.0
    assert_in_delta rate, 100.0, 0.01
  end

  # -------------------------------------------------------
  # Aggregation: empty windows are omitted
  # -------------------------------------------------------

  test "query_agg omits windows with no data points", %{db: db} do
    # Points only in window [0, 1000), nothing in [1000, 2000)
    :ok = TSDB.insert(db, "m", %{}, 100, 1)
    :ok = TSDB.insert(db, "m", %{}, 200, 2)

    [{_labels, agg_points}] = TSDB.query_agg(db, "m", %{}, {0, 2000}, :sum, 1_000)

    assert agg_points == [{0, 3}]
  end

  # -------------------------------------------------------
  # Aggregation: multiple series
  # -------------------------------------------------------

  test "query_agg returns separate aggregations per matched series", %{db: db} do
    :ok = TSDB.insert(db, "cpu", %{"host" => "a"}, 100, 10)
    :ok = TSDB.insert(db, "cpu", %{"host" => "a"}, 200, 20)
    :ok = TSDB.insert(db, "cpu", %{"host" => "b"}, 100, 100)
    :ok = TSDB.insert(db, "cpu", %{"host" => "b"}, 200, 200)

    result = TSDB.query_agg(db, "cpu", %{}, {0, 1000}, :sum, 1_000)

    assert length(result) == 2

    sums =
      result
      |> Enum.map(fn {labels, [{0, sum}]} -> {labels["host"], sum} end)
      |> Enum.sort()

    assert sums == [{"a", 30}, {"b", 300}]
  end

  # -------------------------------------------------------
  # Aggregation: step boundaries
  # -------------------------------------------------------

  test "query_agg correctly buckets across multiple step windows", %{db: db} do
    # step_ms = 500, range [0, 2000)
    # Window [0, 500): t=100 v=1, t=200 v=2
    :ok = TSDB.insert(db, "m", %{}, 100, 1)
    :ok = TSDB.insert(db, "m", %{}, 200, 2)
    # Window [500, 1000): t=600 v=10
    :ok = TSDB.insert(db, "m", %{}, 600, 10)
    # Window [1000, 1500): empty
    # Window [1500, 2000): t=1700 v=99
    :ok = TSDB.insert(db, "m", %{}, 1700, 99)

    [{_labels, agg_points}] = TSDB.query_agg(db, "m", %{}, {0, 2000}, :sum, 500)

    assert agg_points == [{0, 3}, {500, 10}, {1500, 99}]
  end

  # -------------------------------------------------------
  # Cleanup
  # -------------------------------------------------------

  test "cleanup removes expired chunks", %{db: db} do
    # retention_ms = 10_000, chunk_duration_ms = 1_000
    # Insert at t=100 → chunk_start=0, expires when now > 0 + 1000 + 10_000 = 11_000
    :ok = TSDB.insert(db, "m", %{}, 100, 1)
    # Insert at t=5000 → chunk_start=5000, expires when now > 5000 + 1000 + 10_000 = 16_000
    :ok = TSDB.insert(db, "m", %{}, 5000, 2)

    # At time 12_000, the first chunk is expired but the second is not
    Clock.set(12_000)
    send(db, :cleanup)
    :sys.get_state(db)

    result = TSDB.query(db, "m", %{}, {0, 20_000})
    [{_labels, points}] = result
    assert points == [{5000, 2}]
  end

  test "cleanup removes series with no remaining chunks", %{db: db} do
    :ok = TSDB.insert(db, "m", %{"host" => "a"}, 100, 1)

    # Advance well past retention
    Clock.set(100_000)
    send(db, :cleanup)
    :sys.get_state(db)

    # Series should be gone entirely
    assert [] = TSDB.query(db, "m", %{"host" => "a"}, {0, 200_000})

    # Verify internal state is clean
    state = :sys.get_state(db)
    assert map_size(state.series) == 0
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "insert and query with empty labels", %{db: db} do
    :ok = TSDB.insert(db, "m", %{}, 100, 42)

    [{labels, [{100, 42}]}] = TSDB.query(db, "m", %{}, {0, 200})
    assert labels == %{}
  end

  test "query_agg with no matching data returns empty list", %{db: db} do
    assert [] = TSDB.query_agg(db, "nonexistent", %{}, {0, 1000}, :sum, 500)
  end

  test "inserting integer and float values both work", %{db: db} do
    :ok = TSDB.insert(db, "m", %{}, 100, 42)
    :ok = TSDB.insert(db, "m", %{}, 200, 3.14)

    [{_labels, points}] = TSDB.query(db, "m", %{}, {0, 300})
    assert points == [{100, 42}, {200, 3.14}]
  end

  test "points exactly on chunk boundaries go into the correct chunk", %{db: db} do
    # chunk_duration_ms = 1_000
    # t=1000 should go into chunk_start=1000, not chunk_start=0
    :ok = TSDB.insert(db, "m", %{}, 999, 1)
    :ok = TSDB.insert(db, "m", %{}, 1000, 2)
    :ok = TSDB.insert(db, "m", %{}, 1001, 3)

    # Query only chunk [1000, 2000)
    [{_labels, points}] = TSDB.query(db, "m", %{}, {1000, 1999})
    assert points == [{1000, 2}, {1001, 3}]
  end
end
```
