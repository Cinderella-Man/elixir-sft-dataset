# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule CounterTSDB do
  use GenServer

  @default_chunk_duration_ms 60_000
  @default_retention_ms 3_600_000
  @default_cleanup_interval_ms 60_000

  # --------------------------------------------------------------------------
  # Public API
  # --------------------------------------------------------------------------

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  def insert(server, metric_name, labels, timestamp, value) do
    GenServer.call(server, {:insert, metric_name, labels, timestamp, value})
  end

  def query(server, metric_name, label_matchers, {start_ts, end_ts}) do
    GenServer.call(server, {:query, metric_name, label_matchers, {start_ts, end_ts}})
  end

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

  defp series_key(metric, labels), do: {metric, Enum.sort(Map.to_list(labels))}

  defp insert_by_ts([], _ts, point), do: [point]

  defp insert_by_ts([{head_ts, _v} = head | rest], ts, point) when head_ts <= ts do
    [head | insert_by_ts(rest, ts, point)]
  end

  defp insert_by_ts(list, _ts, point), do: [point | list]

  defp matching_series(state, metric, matchers) do
    state.series
    |> Enum.filter(fn {{name, _sorted}, entry} ->
      name == metric and matches?(entry.labels, matchers)
    end)
    |> Enum.map(fn {_key, entry} -> entry end)
  end

  defp matches?(labels, matchers) do
    Enum.all?(matchers, fn {k, v} -> Map.get(labels, k) == v end)
  end

  defp series_points(entry) do
    entry.chunks
    |> Map.values()
    |> Enum.concat()
    |> Enum.sort_by(fn {ts, _v} -> ts end)
  end

  defp windows(start_ts, end_ts, _step) when start_ts >= end_ts, do: []

  defp windows(start_ts, end_ts, step) do
    start_ts
    |> Stream.iterate(&(&1 + step))
    |> Enum.take_while(&(&1 < end_ts))
  end

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

  defp reset_aware_increase(points) do
    points
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce(0, fn [{_pts, prev}, {_cts, cur}], acc ->
      delta = if cur >= prev, do: cur - prev, else: cur
      acc + delta
    end)
  end

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

  defp schedule_cleanup(:infinity), do: :ok
  defp schedule_cleanup(interval), do: Process.send_after(self(), :cleanup, interval)
end
```
