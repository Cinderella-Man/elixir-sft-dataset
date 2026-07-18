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
defmodule TSDB do
  use GenServer

  # ---------------------------------------------------------------------------
  # Types
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # Default options
  # ---------------------------------------------------------------------------

  @default_chunk_duration_ms 60_000
  @default_retention_ms 3_600_000
  @default_cleanup_interval_ms 60_000

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    {name_opts, init_opts} =
      case Keyword.pop(opts, :name) do
        {nil, rest} -> {[], rest}
        {name, rest} -> {[name: name], rest}
      end

    GenServer.start_link(__MODULE__, init_opts, name_opts)
  end

  def insert(server, metric_name, labels, timestamp, value) do
    GenServer.cast(server, {:insert, metric_name, labels, timestamp, value})
  end

  def query(server, metric_name, label_matchers, {start_ts, end_ts}) do
    GenServer.call(server, {:query, metric_name, label_matchers, start_ts, end_ts})
  end

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
