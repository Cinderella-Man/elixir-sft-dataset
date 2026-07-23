# Add moduledoc, docs, and specs

Below: a correct, tested, undocumented module. Deliver the same module
fully documented — a `@moduledoc`, a per-public-function `@doc` and
`@spec`, and supporting `@type`s where useful. Behavior, names, structure:
unchanged. One file.

## The module

```elixir
defmodule FixedWindowLimiter do
  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)

    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  def check(server, key, max_requests, window_ms)
      when is_integer(max_requests) and max_requests > 0 and
             is_integer(window_ms) and window_ms > 0 do
    GenServer.call(server, {:check, key, max_requests, window_ms})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @default_cleanup_interval_ms 60_000

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    cleanup_interval = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)

    schedule_cleanup(cleanup_interval)

    {:ok,
     %{
       # %{{key, window_index} => {count, window_end_time}}
       counters: %{},
       clock: clock,
       cleanup_interval_ms: cleanup_interval
     }}
  end

  @impl true
  def handle_call({:check, key, max_requests, window_ms}, _from, state) do
    now = state.clock.()

    # Snap `now` into the absolute window it belongs to.
    window_index = div(now, window_ms)
    window_end = (window_index + 1) * window_ms
    counter_key = {key, window_index}

    count = Map.get(state.counters, counter_key, {0, window_end}) |> elem(0)

    if count < max_requests do
      new_count = count + 1
      remaining = max_requests - new_count
      new_counters = Map.put(state.counters, counter_key, {new_count, window_end})

      {:reply, {:ok, remaining}, %{state | counters: new_counters}}
    else
      # Counter saturated; wait until this window ends.
      retry_after = max(window_end - now, 1)
      {:reply, {:error, :rate_limited, retry_after}, state}
    end
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = state.clock.()

    cleaned =
      state.counters
      |> Enum.reduce(%{}, fn {ck, {count, window_end} = entry}, acc ->
        # Keep only counters whose window has not yet ended.
        if window_end > now do
          Map.put(acc, ck, entry)
        else
          _ = count
          acc
        end
      end)

    schedule_cleanup(state.cleanup_interval_ms)

    {:noreply, %{state | counters: cleaned}}
  end

  # Catch-all so unexpected messages don't crash the process.
  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp schedule_cleanup(:infinity), do: :ok

  defp schedule_cleanup(interval_ms) when is_integer(interval_ms) do
    Process.send_after(self(), :cleanup, interval_ms)
  end
end
```
