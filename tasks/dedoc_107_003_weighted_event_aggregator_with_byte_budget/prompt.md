# Add moduledoc, docs, and specs

Below: a correct, tested, undocumented module. Deliver the same module
fully documented — a `@moduledoc`, a per-public-function `@doc` and
`@spec`, and supporting `@type`s where useful. Behavior, names, structure:
unchanged. One file.

## The module

```elixir
defmodule WeightedAggregator do
  use GenServer

  @default_max_bytes 1_048_576
  @default_interval_ms 1_000
  @default_size_fn &byte_size/1
  @default_on_flush &WeightedAggregator.__noop__/1

  ## Public API

  def start_link(opts \\ []) when is_list(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  def push(server, event) do
    GenServer.cast(server, {:push, event})
  end

  def __noop__(_batch), do: :ok

  ## GenServer callbacks

  @impl true
  def init(opts) do
    state = %{
      max_bytes: Keyword.get(opts, :max_bytes, @default_max_bytes),
      interval_ms: Keyword.get(opts, :interval_ms, @default_interval_ms),
      size_fn: Keyword.get(opts, :size_fn, @default_size_fn),
      on_flush: Keyword.get(opts, :on_flush, @default_on_flush),
      # Buffer stored in reverse push order for O(1) prepend; reversed into push
      # order right before being handed to the callback.
      buffer: [],
      weight: 0,
      timer: nil,
      timer_ref: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:push, event}, state) do
    weight = state.size_fn.(event)

    state =
      %{state | buffer: [event | state.buffer], weight: state.weight + weight}
      |> ensure_timer()

    state =
      if state.weight >= state.max_bytes do
        flush(state)
      else
        state
      end

    {:noreply, state}
  end

  @impl true
  def handle_info({:flush, ref}, %{timer_ref: ref} = state) do
    state =
      if state.buffer == [] do
        clear_timer(state)
      else
        flush(state)
      end

    {:noreply, state}
  end

  def handle_info({:flush, _stale_ref}, state) do
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Internal helpers

  # Start the interval timer only on the transition from empty to non-empty.
  defp ensure_timer(%{timer: nil} = state), do: start_timer(state)
  defp ensure_timer(state), do: state

  defp start_timer(state) do
    ref = make_ref()
    timer = Process.send_after(self(), {:flush, ref}, state.interval_ms)
    %{state | timer: timer, timer_ref: ref}
  end

  defp clear_timer(%{timer: nil} = state), do: state

  defp clear_timer(state) do
    Process.cancel_timer(state.timer)
    %{state | timer: nil, timer_ref: nil}
  end

  # Deliver the buffered events (in push order) to the callback, then reset the
  # buffer, the accumulated weight, and the interval timer.
  defp flush(%{buffer: []} = state), do: state

  defp flush(state) do
    batch = Enum.reverse(state.buffer)
    state.on_flush.(batch)

    state
    |> clear_timer()
    |> Map.merge(%{buffer: [], weight: 0})
  end
end
```
