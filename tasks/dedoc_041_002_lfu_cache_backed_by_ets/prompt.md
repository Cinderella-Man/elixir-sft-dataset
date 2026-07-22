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
defmodule LFUCache do
  use GenServer

  def child_spec(opts) do
    name = Keyword.fetch!(opts, :name)

    %{
      id: name,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5_000
    }
  end

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def get(name, key) do
    case :ets.lookup(data_table_name(name), key) do
      [{^key, {value, _freq, _seq}}] ->
        GenServer.call(name, {:touch, key})
        {:ok, value}

      [] ->
        :miss
    end
  end

  def put(name, key, value) do
    GenServer.call(name, {:put, key, value})
  end

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)

    # A missing :max_size fails like an invalid one — ArgumentError, not the
    # KeyError a fetch! would raise (the contract reserves that for :name).
    max_size =
      case Keyword.fetch(opts, :max_size) do
        {:ok, value} -> value
        :error -> raise ArgumentError, ":max_size is required"
      end

    unless is_integer(max_size) and max_size > 0 do
      raise ArgumentError, ":max_size must be a positive integer, got: #{inspect(max_size)}"
    end

    data_table =
      :ets.new(data_table_name(name), [
        :set,
        :public,
        :named_table,
        read_concurrency: true
      ])

    order_table =
      :ets.new(order_table_name(name), [
        :ordered_set,
        :protected,
        :named_table
      ])

    state = %{
      data_table: data_table,
      order_table: order_table,
      max_size: max_size,
      counter: 0
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:touch, key}, _from, state) do
    case :ets.lookup(state.data_table, key) do
      [{^key, {value, freq, seq}}] ->
        {new_seq, state} = next_counter(state)
        :ets.delete(state.order_table, {freq, seq})
        :ets.insert(state.order_table, {{freq + 1, new_seq}, key})
        :ets.insert(state.data_table, {key, {value, freq + 1, new_seq}})
        {:reply, :ok, state}

      [] ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:put, key, value}, _from, state) do
    state =
      case :ets.lookup(state.data_table, key) do
        [{^key, {_old_value, freq, seq}}] ->
          {new_seq, state} = next_counter(state)
          :ets.delete(state.order_table, {freq, seq})
          :ets.insert(state.order_table, {{freq + 1, new_seq}, key})
          :ets.insert(state.data_table, {key, {value, freq + 1, new_seq}})
          state

        [] ->
          state = maybe_evict(state)
          {new_seq, state} = next_counter(state)
          :ets.insert(state.order_table, {{1, new_seq}, key})
          :ets.insert(state.data_table, {key, {value, 1, new_seq}})
          state
      end

    {:reply, :ok, state}
  end

  defp next_counter(%{counter: c} = state), do: {c + 1, %{state | counter: c + 1}}

  defp maybe_evict(state) do
    if :ets.info(state.data_table, :size) >= state.max_size do
      # Smallest composite key = lowest frequency, LRU tie-break.
      victim_composite = :ets.first(state.order_table)
      [{^victim_composite, victim_key}] = :ets.lookup(state.order_table, victim_composite)
      :ets.delete(state.order_table, victim_composite)
      :ets.delete(state.data_table, victim_key)
    end

    state
  end

  defp data_table_name(name), do: :"#{name}_data"
  defp order_table_name(name), do: :"#{name}_order"
end
```
