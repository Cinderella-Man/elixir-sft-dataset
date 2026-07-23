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
defmodule RejectingRingBuffer do
  @enforce_keys [:capacity, :store, :read, :write, :size]
  defstruct [:capacity, :store, :read, :write, :size]

  def new(capacity) when is_integer(capacity) and capacity > 0 do
    %__MODULE__{
      capacity: capacity,
      store: :erlang.make_tuple(capacity, nil),
      read: 0,
      write: 0,
      size: 0
    }
  end

  def push(%__MODULE__{size: size, capacity: capacity}, _item) when size == capacity do
    {:error, :full}
  end

  def push(%__MODULE__{capacity: cap, store: store, write: write, size: size} = buf, item) do
    new_store = :erlang.setelement(write + 1, store, item)
    {:ok, %{buf | store: new_store, write: rem(write + 1, cap), size: size + 1}}
  end

  def pop(%__MODULE__{size: 0}), do: :empty

  def pop(%__MODULE__{capacity: cap, store: store, read: read, size: size} = buf) do
    item = :erlang.element(read + 1, store)
    {:ok, item, %{buf | read: rem(read + 1, cap), size: size - 1}}
  end

  def to_list(%__MODULE__{size: 0}), do: []

  def to_list(%__MODULE__{capacity: cap, store: store, read: read, size: size}) do
    Enum.map(0..(size - 1), fn offset ->
      :erlang.element(rem(read + offset, cap) + 1, store)
    end)
  end

  def size(%__MODULE__{size: size}), do: size

  def full?(%__MODULE__{size: size, capacity: capacity}), do: size == capacity

  def peek_oldest(%__MODULE__{size: 0}), do: :error

  def peek_oldest(%__MODULE__{store: store, read: read}) do
    {:ok, :erlang.element(read + 1, store)}
  end

  def peek_newest(%__MODULE__{size: 0}), do: :error

  def peek_newest(%__MODULE__{capacity: cap, store: store, write: write}) do
    newest_index = rem(write - 1 + cap, cap)
    {:ok, :erlang.element(newest_index + 1, store)}
  end
end
```
