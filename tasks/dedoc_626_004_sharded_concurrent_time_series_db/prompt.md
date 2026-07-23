# Add moduledoc, docs, and specs

Below: a correct, tested, undocumented module. Deliver the same module
fully documented — a `@moduledoc`, a per-public-function `@doc` and
`@spec`, and supporting `@type`s where useful. Behavior, names, structure:
unchanged. One file.

## The module

```elixir
defmodule ShardedTSDB do
  use GenServer

  # ── Public API ────────────────────────────────────────────────────────

  def start_link(opts) do
    name = Keyword.get(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  def insert(server, metric_name, labels, timestamp, value) do
    GenServer.call(server, {:insert, metric_name, labels, timestamp, value})
  end

  def query(server, metric_name, label_matchers, {start_ts, end_ts}) do
    GenServer.call(server, {:query, metric_name, label_matchers, {start_ts, end_ts}})
  end

  def query_agg(server, metric_name, label_matchers, {start_ts, end_ts}, aggregation, step_ms) do
    msg = {:query_agg, metric_name, label_matchers, {start_ts, end_ts}, aggregation, step_ms}
    GenServer.call(server, msg)
  end

  def shard_count(server) do
    GenServer.call(server, :shard_count)
  end

  def shard_of(server, metric_name, labels) do
    GenServer.call(server, {:shard_of, metric_name, labels})
  end

  def series_count(server) do
    GenServer.call(server, :series_count)
  end

  def cleanup(server) do
    GenServer.call(server, :cleanup)
  end

  # ── Coordinator callbacks ─────────────────────────────────────────────

  @impl true
  def init(opts) do
    count = Keyword.get(opts, :shards, 4)
    chunk = Keyword.get(opts, :chunk_duration_ms, 60_000)
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    retention = Keyword.get(opts, :retention_ms, 3_600_000)
    interval = Keyword.get(opts, :cleanup_interval_ms, 60_000)

    shards =
      for _ <- 1..count do
        {:ok, pid} = ShardedTSDB.Shard.start_link(chunk)
        pid
      end

    state = %{
      shards: List.to_tuple(shards),
      shard_count: count,
      chunk_duration_ms: chunk,
      clock: clock,
      retention_ms: retention,
      cleanup_interval_ms: interval
    }

    schedule_cleanup(state)
    {:ok, state}
  end

  @impl true
  def handle_call({:insert, metric, labels, ts, value}, _from, state) do
    key = series_key(metric, labels)
    idx = :erlang.phash2(key, state.shard_count)
    pid = elem(state.shards, idx)
    :ok = GenServer.call(pid, {:insert, key, ts, value})
    {:reply, :ok, state}
  end

  def handle_call({:query, metric, matchers, range}, _from, state) do
    results =
      state.shards
      |> Tuple.to_list()
      |> Enum.flat_map(fn pid -> GenServer.call(pid, {:query, metric, matchers, range}) end)

    {:reply, results, state}
  end

  def handle_call({:query_agg, metric, matchers, range, agg, step}, _from, state) do
    msg = {:query_agg, metric, matchers, range, agg, step}

    results =
      state.shards
      |> Tuple.to_list()
      |> Enum.flat_map(fn pid -> GenServer.call(pid, msg) end)

    {:reply, results, state}
  end

  def handle_call(:shard_count, _from, state) do
    {:reply, state.shard_count, state}
  end

  def handle_call({:shard_of, metric, labels}, _from, state) do
    idx = :erlang.phash2(series_key(metric, labels), state.shard_count)
    {:reply, idx, state}
  end

  def handle_call(:series_count, _from, state) do
    total =
      state.shards
      |> Tuple.to_list()
      |> Enum.reduce(0, fn pid, acc -> acc + GenServer.call(pid, :series_count) end)

    {:reply, total, state}
  end

  def handle_call(:cleanup, _from, state) do
    do_cleanup(state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:cleanup_tick, state) do
    do_cleanup(state)
    schedule_cleanup(state)
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ── Coordinator helpers ───────────────────────────────────────────────

  defp series_key(metric, labels) do
    {metric, Enum.sort(Map.to_list(labels))}
  end

  defp schedule_cleanup(%{cleanup_interval_ms: :infinity}), do: :ok

  defp schedule_cleanup(%{cleanup_interval_ms: interval}) do
    Process.send_after(self(), :cleanup_tick, interval)
    :ok
  end

  defp do_cleanup(state) do
    cutoff = state.clock.() - state.retention_ms

    state.shards
    |> Tuple.to_list()
    |> Enum.each(fn pid -> GenServer.call(pid, {:cleanup, cutoff}) end)

    :ok
  end
end

defmodule ShardedTSDB.Shard do
  use GenServer

  def start_link(chunk_duration_ms) do
    GenServer.start_link(__MODULE__, chunk_duration_ms)
  end

  @impl true
  def init(chunk_duration_ms) do
    {:ok, %{chunk_duration_ms: chunk_duration_ms, data: %{}}}
  end

  @impl true
  def handle_call({:insert, key, ts, value}, _from, state) do
    chunk_start = div(ts, state.chunk_duration_ms) * state.chunk_duration_ms
    series = Map.get(state.data, key, %{})
    chunk = Map.get(series, chunk_start, [])
    new_chunk = Enum.sort_by([{ts, value} | chunk], fn {t, _} -> t end)
    new_series = Map.put(series, chunk_start, new_chunk)
    new_data = Map.put(state.data, key, new_series)
    {:reply, :ok, %{state | data: new_data}}
  end

  def handle_call({:query, metric, matchers, {start_ts, end_ts}}, _from, state) do
    results =
      for {{m, sorted_labels} = _key, chunks} <- state.data,
          m == metric,
          label_match?(sorted_labels, matchers),
          points = in_range_points(chunks, start_ts, end_ts),
          points != [],
          do: {Map.new(sorted_labels), points}

    {:reply, results, state}
  end

  def handle_call({:query_agg, metric, matchers, range, agg, step}, _from, state) do
    {start_ts, end_ts} = range

    results =
      for {{m, sorted_labels}, chunks} <- state.data,
          m == metric,
          label_match?(sorted_labels, matchers),
          agg_points = aggregate(chunks, start_ts, end_ts, step, agg),
          agg_points != [],
          do: {Map.new(sorted_labels), agg_points}

    {:reply, results, state}
  end

  def handle_call(:series_count, _from, state) do
    {:reply, map_size(state.data), state}
  end

  def handle_call({:cleanup, cutoff}, _from, state) do
    new_data =
      Enum.reduce(state.data, %{}, fn {key, chunks}, acc ->
        kept =
          for {cs, pts} <- chunks,
              cs + state.chunk_duration_ms > cutoff,
              into: %{},
              do: {cs, pts}

        if map_size(kept) == 0, do: acc, else: Map.put(acc, key, kept)
      end)

    {:reply, :ok, %{state | data: new_data}}
  end

  # ── Shard helpers ─────────────────────────────────────────────────────

  defp label_match?(sorted_labels, matchers) do
    lmap = Map.new(sorted_labels)
    Enum.all?(matchers, fn {k, v} -> Map.fetch(lmap, k) == {:ok, v} end)
  end

  defp in_range_points(chunks, start_ts, end_ts) do
    chunks
    |> Map.values()
    |> Enum.concat()
    |> Enum.filter(fn {ts, _} -> ts >= start_ts and ts <= end_ts end)
    |> Enum.sort_by(fn {ts, _} -> ts end)
  end

  defp aggregate(chunks, start_ts, end_ts, step, agg) do
    chunks
    |> Map.values()
    |> Enum.concat()
    |> Enum.filter(fn {ts, _} -> ts >= start_ts and ts < end_ts end)
    |> Enum.group_by(
      fn {ts, _} -> start_ts + div(ts - start_ts, step) * step end,
      fn {_, v} -> v end
    )
    |> Enum.map(fn {window_start, vals} -> {window_start, apply_agg(agg, vals)} end)
    |> Enum.sort_by(fn {window_start, _} -> window_start end)
  end

  defp apply_agg(:sum, vals), do: Enum.sum(vals)
  defp apply_agg(:avg, vals), do: Enum.sum(vals) / length(vals)
  defp apply_agg(:max, vals), do: Enum.max(vals)
end
```
