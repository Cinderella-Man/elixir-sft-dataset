# Add moduledoc, docs, and specs

Below: a correct, tested, undocumented module. Deliver the same module
fully documented — a `@moduledoc`, a per-public-function `@doc` and
`@spec`, and supporting `@type`s where useful. Behavior, names, structure:
unchanged. One file.

## The module

```elixir
defmodule SlidingUniqueCounter do
  use GenServer

  @default_bucket_ms 1_000
  @default_cleanup_interval_ms 60_000
  @default_max_window_ms 3_600_000

  def start_link(opts) when is_list(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  def add(server, key, member) do
    GenServer.call(server, {:add, key, member})
  end

  def distinct_count(server, key, window_ms) do
    GenServer.call(server, {:distinct_count, key, window_ms})
  end

  def tracked_key_count(server) do
    GenServer.call(server, :tracked_key_count)
  end

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    bucket_ms = Keyword.get(opts, :bucket_ms, @default_bucket_ms)
    cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)
    max_window_ms = Keyword.get(opts, :max_window_ms, @default_max_window_ms)

    state = %{
      clock: clock,
      bucket_ms: bucket_ms,
      cleanup_interval_ms: cleanup_interval_ms,
      max_window_ms: max_window_ms,
      keys: %{}
    }

    schedule_cleanup(cleanup_interval_ms)
    {:ok, state}
  end

  @impl true
  def handle_call({:add, key, member}, _from, state) do
    now = state.clock.()
    index = div(now, state.bucket_ms)

    buckets = Map.get(state.keys, key, %{})
    set = Map.get(buckets, index, MapSet.new())
    buckets = Map.put(buckets, index, MapSet.put(set, member))
    keys = Map.put(state.keys, key, buckets)

    {:reply, :ok, %{state | keys: keys}}
  end

  def handle_call({:distinct_count, key, window_ms}, _from, state) do
    now = state.clock.()
    threshold = now - window_ms
    buckets = Map.get(state.keys, key, %{})

    union =
      Enum.reduce(buckets, MapSet.new(), fn {index, set}, acc ->
        if index * state.bucket_ms >= threshold do
          MapSet.union(acc, set)
        else
          acc
        end
      end)

    {:reply, MapSet.size(union), state}
  end

  def handle_call(:tracked_key_count, _from, state) do
    {:reply, map_size(state.keys), state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    state = purge_expired(state)
    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp schedule_cleanup(:infinity), do: :ok

  defp schedule_cleanup(interval_ms) when is_integer(interval_ms) do
    Process.send_after(self(), :cleanup, interval_ms)
    :ok
  end

  defp purge_expired(state) do
    now = state.clock.()
    threshold = now - state.max_window_ms

    keys =
      Enum.reduce(state.keys, %{}, fn {key, buckets}, acc ->
        kept =
          Enum.reduce(buckets, %{}, fn {index, set}, inner ->
            if index * state.bucket_ms >= threshold do
              Map.put(inner, index, set)
            else
              inner
            end
          end)

        if map_size(kept) == 0, do: acc, else: Map.put(acc, key, kept)
      end)

    %{state | keys: keys}
  end
end
```
