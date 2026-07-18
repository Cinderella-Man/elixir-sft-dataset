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
