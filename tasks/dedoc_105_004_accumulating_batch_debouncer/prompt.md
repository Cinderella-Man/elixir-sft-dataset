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
defmodule BatchDebouncer do
  use GenServer

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  def call(key, delay_ms, item, handler)
      when is_integer(delay_ms) and delay_ms >= 0 and is_function(handler, 1) do
    GenServer.cast(__MODULE__, {:submit, key, delay_ms, item, handler})
  end

  def pending(key), do: GenServer.call(__MODULE__, {:pending, key})

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_cast({:submit, key, delay_ms, item, handler}, state) do
    # Items are stored reversed (newest first) and reversed at flush time so we
    # never pay O(n) per append.
    items =
      case Map.get(state, key) do
        %{timer: ref, items: items} ->
          Process.cancel_timer(ref)
          [item | items]

        nil ->
          [item]
      end

    ref = Process.send_after(self(), {:flush, key}, delay_ms)
    entry = %{timer: ref, items: items, handler: handler}
    {:noreply, Map.put(state, key, entry)}
  end

  @impl true
  def handle_call({:pending, key}, _from, state) do
    count =
      case Map.get(state, key) do
        %{items: items} -> length(items)
        nil -> 0
      end

    {:reply, count, state}
  end

  @impl true
  def handle_info({:flush, key}, state) do
    case Map.pop(state, key) do
      {%{items: items, handler: handler}, new_state} ->
        batch = Enum.reverse(items)
        spawn(fn -> handler.(batch) end)
        {:noreply, new_state}

      {nil, new_state} ->
        {:noreply, new_state}
    end
  end
end
```
