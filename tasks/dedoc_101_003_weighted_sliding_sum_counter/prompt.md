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
defmodule SlidingSum do
  use GenServer

  @default_bucket_ms 1_000
  @default_cleanup_interval_ms 60_000

  # Buckets older than this many window-milliseconds are considered expired by
  # the periodic cleanup. It is a generous upper bound on any expected window.
  @max_window_ms 24 * 60 * 60 * 1_000

  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  def add(server, key, amount) when is_number(amount) do
    GenServer.call(server, {:add, key, amount})
  end

  def sum(server, key, window_ms) when is_integer(window_ms) and window_ms >= 0 do
    GenServer.call(server, {:sum, key, window_ms})
  end

  def keys(server) do
    GenServer.call(server, :keys)
  end

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    bucket_ms = Keyword.get(opts, :bucket_ms, @default_bucket_ms)
    cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)

    state = %{
      clock: clock,
      bucket_ms: bucket_ms,
      cleanup_interval_ms: cleanup_interval_ms,
      keys: %{}
    }

    {:ok, schedule_cleanup(state)}
  end

  @impl true
  def handle_call({:add, key, amount}, _from, state) do
    now = state.clock.()
    bucket = div(now, state.bucket_ms)

    buckets = Map.get(state.keys, key, %{})
    buckets = Map.update(buckets, bucket, amount, &(&1 + amount))
    keys = Map.put(state.keys, key, buckets)

    {:reply, :ok, %{state | keys: keys}}
  end

  def handle_call({:sum, key, window_ms}, _from, state) do
    now = state.clock.()
    cutoff = now - window_ms

    total =
      state.keys
      |> Map.get(key, %{})
      |> Enum.reduce(0, fn {bucket, bucket_sum}, acc ->
        if bucket * state.bucket_ms >= cutoff, do: acc + bucket_sum, else: acc
      end)

    {:reply, total, state}
  end

  def handle_call(:keys, _from, state) do
    {:reply, Map.keys(state.keys), state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    {:noreply, state |> cleanup() |> schedule_cleanup()}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp cleanup(state) do
    now = state.clock.()
    cutoff = now - @max_window_ms

    keys =
      state.keys
      |> Enum.reduce(%{}, fn {key, buckets}, acc ->
        kept =
          Enum.filter(buckets, fn {bucket, _sum} ->
            bucket * state.bucket_ms >= cutoff
          end)

        if kept == [], do: acc, else: Map.put(acc, key, Map.new(kept))
      end)

    %{state | keys: keys}
  end

  defp schedule_cleanup(%{cleanup_interval_ms: :infinity} = state), do: state

  defp schedule_cleanup(state) do
    Process.send_after(self(), :cleanup, state.cleanup_interval_ms)
    state
  end
end
```
