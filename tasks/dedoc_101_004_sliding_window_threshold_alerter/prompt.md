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
defmodule SlidingAlerter do
  use GenServer

  @default_bucket_ms 1_000
  @default_threshold 5
  @default_window_ms 60_000
  @default_cleanup_interval_ms 60_000

  # Public API

  def start_link(opts) when is_list(opts) do
    {name, init_opts} = Keyword.pop(opts, :name)

    case name do
      nil -> GenServer.start_link(__MODULE__, init_opts)
      name -> GenServer.start_link(__MODULE__, init_opts, name: name)
    end
  end

  def record(server, key) do
    GenServer.call(server, {:record, key})
  end

  def status(server, key) do
    GenServer.call(server, {:status, key})
  end

  def count(server, key) do
    GenServer.call(server, {:count, key})
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)

    state = %{
      clock: clock,
      bucket_ms: Keyword.get(opts, :bucket_ms, @default_bucket_ms),
      threshold: Keyword.get(opts, :threshold, @default_threshold),
      window_ms: Keyword.get(opts, :window_ms, @default_window_ms),
      cleanup_interval_ms: Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms),
      keys: %{}
    }

    schedule_cleanup(state.cleanup_interval_ms)
    {:ok, state}
  end

  @impl true
  def handle_call({:record, key}, _from, state) do
    now = state.clock.()
    bucket = div(now, state.bucket_ms)

    buckets =
      state.keys
      |> Map.get(key, %{})
      |> Map.update(bucket, 1, &(&1 + 1))

    state = %{state | keys: Map.put(state.keys, key, buckets)}
    {:reply, status_for(buckets, now, state), state}
  end

  @impl true
  def handle_call({:status, key}, _from, state) do
    now = state.clock.()
    buckets = Map.get(state.keys, key, %{})
    {:reply, status_for(buckets, now, state), state}
  end

  @impl true
  def handle_call({:count, key}, _from, state) do
    now = state.clock.()
    buckets = Map.get(state.keys, key, %{})
    {:reply, count_for(buckets, now, state), state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    state = cleanup(state)
    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, state}
  end

  # Internal helpers

  defp schedule_cleanup(:infinity), do: :ok

  defp schedule_cleanup(interval_ms) when is_integer(interval_ms) do
    Process.send_after(self(), :cleanup, interval_ms)
    :ok
  end

  defp count_for(buckets, now, state) do
    cutoff = now - state.window_ms

    Enum.reduce(buckets, 0, fn {bucket, count}, acc ->
      if bucket * state.bucket_ms >= cutoff, do: acc + count, else: acc
    end)
  end

  defp status_for(buckets, now, state) do
    if count_for(buckets, now, state) >= state.threshold, do: :alarm, else: :ok
  end

  defp cleanup(state) do
    now = state.clock.()
    cutoff = now - state.window_ms

    keys =
      state.keys
      |> Enum.reduce(%{}, fn {key, buckets}, acc ->
        live =
          buckets
          |> Enum.filter(fn {bucket, _count} -> bucket * state.bucket_ms >= cutoff end)
          |> Map.new()

        if map_size(live) == 0, do: acc, else: Map.put(acc, key, live)
      end)

    %{state | keys: keys}
  end
end
```
