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
defmodule DebounceAggregator do
  use GenServer

  @default_idle_ms 1_000
  @default_max_wait_ms 5_000
  @default_batch_size :infinity
  @default_on_flush &DebounceAggregator.__noop__/1

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
      idle_ms: Keyword.get(opts, :idle_ms, @default_idle_ms),
      max_wait_ms: Keyword.get(opts, :max_wait_ms, @default_max_wait_ms),
      batch_size: Keyword.get(opts, :batch_size, @default_batch_size),
      on_flush: Keyword.get(opts, :on_flush, @default_on_flush),
      # Buffer stored in reverse push order; reversed at flush time.
      buffer: [],
      count: 0,
      # `gen` tags the current batch's timers so stale timer messages from a
      # superseded batch are ignored.
      gen: nil,
      idle_timer: nil,
      max_timer: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:push, event}, state) do
    # A push into an empty buffer begins a new batch and arms the max-wait cap.
    state = if state.count == 0, do: start_batch(state), else: state

    state = %{state | buffer: [event | state.buffer], count: state.count + 1}

    # The idle timer is (re)armed on every push — this is the debounce.
    state = reset_idle(state)

    state =
      if size_reached?(state) do
        flush(state)
      else
        state
      end

    {:noreply, state}
  end

  @impl true
  def handle_info({:idle_flush, gen}, %{gen: gen} = state) when gen != nil do
    {:noreply, flush(state)}
  end

  def handle_info({:max_flush, gen}, %{gen: gen} = state) when gen != nil do
    {:noreply, flush(state)}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Internal helpers

  defp size_reached?(%{batch_size: :infinity}), do: false
  defp size_reached?(%{count: count, batch_size: size}), do: count >= size

  defp start_batch(state) do
    gen = make_ref()
    max_timer = Process.send_after(self(), {:max_flush, gen}, state.max_wait_ms)
    %{state | gen: gen, max_timer: max_timer}
  end

  defp reset_idle(state) do
    if state.idle_timer, do: Process.cancel_timer(state.idle_timer)
    timer = Process.send_after(self(), {:idle_flush, state.gen}, state.idle_ms)
    %{state | idle_timer: timer}
  end

  # Deliver buffered events (in push order) to the callback and clear both timers
  # so the next push begins a brand-new batch.
  defp flush(%{count: 0} = state), do: state

  defp flush(state) do
    batch = Enum.reverse(state.buffer)
    state.on_flush.(batch)

    if state.idle_timer, do: Process.cancel_timer(state.idle_timer)
    if state.max_timer, do: Process.cancel_timer(state.max_timer)

    %{state | buffer: [], count: 0, gen: nil, idle_timer: nil, max_timer: nil}
  end
end
```
