# Add moduledoc, docs, and specs

Below: a correct, tested, undocumented module. Deliver the same module
fully documented — a `@moduledoc`, a per-public-function `@doc` and
`@spec`, and supporting `@type`s where useful. Behavior, names, structure:
unchanged. One file.

## The module

```elixir
defmodule MaxWaitDebouncer do
  use GenServer

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  def call(key, delay_ms, max_ms, func)
      when is_integer(delay_ms) and delay_ms >= 0 and is_integer(max_ms) and
             max_ms >= delay_ms and
             is_function(func, 0) do
    GenServer.cast(__MODULE__, {:debounce, key, delay_ms, max_ms, func})
  end

  def flush(key), do: GenServer.call(__MODULE__, {:flush, key})

  def cancel(key), do: GenServer.call(__MODULE__, {:cancel, key})

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_cast({:debounce, key, delay_ms, max_ms, func}, state) do
    now = mono_ms()

    first_at =
      case Map.get(state, key) do
        %{timer: ref, first_at: at} ->
          Process.cancel_timer(ref)
          at

        nil ->
          now
      end

    remaining_until_max = max(0, first_at + max_ms - now)
    fire_in = max(0, min(delay_ms, remaining_until_max))
    ref = Process.send_after(self(), {:fire, key}, fire_in)

    entry = %{timer: ref, func: func, first_at: first_at}
    {:noreply, Map.put(state, key, entry)}
  end

  @impl true
  def handle_call({:flush, key}, _from, state) do
    case Map.pop(state, key) do
      {%{timer: ref, func: func}, new_state} ->
        Process.cancel_timer(ref)
        run(func)
        {:reply, :ok, new_state}

      {nil, new_state} ->
        {:reply, :ok, new_state}
    end
  end

  def handle_call({:cancel, key}, _from, state) do
    case Map.pop(state, key) do
      {%{timer: ref}, new_state} ->
        Process.cancel_timer(ref)
        {:reply, :ok, new_state}

      {nil, new_state} ->
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_info({:fire, key}, state) do
    case Map.pop(state, key) do
      {%{func: func}, new_state} ->
        run(func)
        {:noreply, new_state}

      {nil, new_state} ->
        {:noreply, new_state}
    end
  end

  defp run(func), do: spawn(fn -> func.() end)

  defp mono_ms, do: System.monotonic_time(:millisecond)
end
```
