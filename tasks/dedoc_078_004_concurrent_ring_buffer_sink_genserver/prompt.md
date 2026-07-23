# Restore the documentation

The module below works and is fully tested — its behavior is final. What it
lost is every piece of documentation. Put it back:

- a `@moduledoc` covering purpose and usage,
- a `@doc` on each public function,
- a `@spec` on each public function (plus `@type`s where they clarify).

And keep your hands off the code itself: no renames, no refactors, no added
or removed functions, identical behavior everywhere. Return the whole
documented module in one file.

## The module

```elixir
defmodule ConcurrentRingBuffer do
  use GenServer

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  def start_link(opts) when is_list(opts) do
    {capacity, opts} = Keyword.pop(opts, :capacity)
    GenServer.start_link(__MODULE__, capacity, opts)
  end

  def push(server, item), do: GenServer.call(server, {:push, item})

  def to_list(server), do: GenServer.call(server, :to_list)

  def size(server), do: GenServer.call(server, :size)

  def peek_oldest(server), do: GenServer.call(server, :peek_oldest)

  def peek_newest(server), do: GenServer.call(server, :peek_newest)

  def flush(server), do: GenServer.call(server, :flush)

  # ---------------------------------------------------------------------------
  # Server callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(capacity) when is_integer(capacity) and capacity > 0 do
    {:ok, fresh_state(capacity)}
  end

  @impl true
  def handle_call({:push, item}, _from, state) do
    {:reply, :ok, do_push(state, item)}
  end

  def handle_call(:to_list, _from, state) do
    {:reply, do_to_list(state), state}
  end

  def handle_call(:size, _from, state) do
    {:reply, state.size, state}
  end

  def handle_call(:peek_oldest, _from, state) do
    {:reply, do_peek_oldest(state), state}
  end

  def handle_call(:peek_newest, _from, state) do
    {:reply, do_peek_newest(state), state}
  end

  def handle_call(:flush, _from, state) do
    {:reply, do_to_list(state), fresh_state(state.capacity)}
  end

  # ---------------------------------------------------------------------------
  # Internal ring-buffer logic (pure, over the state map)
  # ---------------------------------------------------------------------------

  defp fresh_state(capacity) do
    %{
      capacity: capacity,
      store: :erlang.make_tuple(capacity, nil),
      read: 0,
      write: 0,
      size: 0
    }
  end

  defp do_push(state, item) do
    %{capacity: cap, store: store, read: read, write: write, size: size} = state
    new_store = :erlang.setelement(write + 1, store, item)
    new_write = rem(write + 1, cap)

    if size == cap do
      %{state | store: new_store, write: new_write, read: rem(read + 1, cap)}
    else
      %{state | store: new_store, write: new_write, size: size + 1}
    end
  end

  defp do_to_list(%{size: 0}), do: []

  defp do_to_list(%{capacity: cap, store: store, read: read, size: size}) do
    Enum.map(0..(size - 1), fn offset ->
      :erlang.element(rem(read + offset, cap) + 1, store)
    end)
  end

  defp do_peek_oldest(%{size: 0}), do: :error

  defp do_peek_oldest(%{store: store, read: read}) do
    {:ok, :erlang.element(read + 1, store)}
  end

  defp do_peek_newest(%{size: 0}), do: :error

  defp do_peek_newest(%{capacity: cap, store: store, write: write}) do
    newest_index = rem(write - 1 + cap, cap)
    {:ok, :erlang.element(newest_index + 1, store)}
  end
end
```
