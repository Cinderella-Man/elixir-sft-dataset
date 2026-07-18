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
defmodule RingDeque do
  @enforce_keys [:capacity, :store, :head, :size]
  defstruct [:capacity, :store, :head, :size]

  def new(capacity) when is_integer(capacity) and capacity > 0 do
    %__MODULE__{
      capacity: capacity,
      store: :erlang.make_tuple(capacity, nil),
      head: 0,
      size: 0
    }
  end

  def push_back(%__MODULE__{capacity: cap, store: store, head: head, size: size} = d, item) do
    slot = rem(head + size, cap)
    new_store = :erlang.setelement(slot + 1, store, item)

    if size == cap do
      # Full: the write landed on the old front slot; advance head to drop it.
      %{d | store: new_store, head: rem(head + 1, cap)}
    else
      %{d | store: new_store, size: size + 1}
    end
  end

  def push_front(%__MODULE__{capacity: cap, store: store, head: head, size: size} = d, item) do
    new_head = rem(head - 1 + cap, cap)
    new_store = :erlang.setelement(new_head + 1, store, item)

    if size == cap do
      # Full: new_head coincides with the old back slot, dropping it.
      %{d | store: new_store, head: new_head}
    else
      %{d | store: new_store, head: new_head, size: size + 1}
    end
  end

  def pop_front(%__MODULE__{size: 0}), do: :empty

  def pop_front(%__MODULE__{capacity: cap, store: store, head: head, size: size} = d) do
    item = :erlang.element(head + 1, store)
    {:ok, item, %{d | head: rem(head + 1, cap), size: size - 1}}
  end

  def pop_back(%__MODULE__{size: 0}), do: :empty

  def pop_back(%__MODULE__{capacity: cap, store: store, head: head, size: size} = d) do
    slot = rem(head + size - 1, cap)
    item = :erlang.element(slot + 1, store)
    {:ok, item, %{d | size: size - 1}}
  end

  def to_list(%__MODULE__{size: 0}), do: []

  def to_list(%__MODULE__{capacity: cap, store: store, head: head, size: size}) do
    Enum.map(0..(size - 1), fn offset ->
      :erlang.element(rem(head + offset, cap) + 1, store)
    end)
  end

  def size(%__MODULE__{size: size}), do: size

  def peek_front(%__MODULE__{size: 0}), do: :error

  def peek_front(%__MODULE__{store: store, head: head}) do
    {:ok, :erlang.element(head + 1, store)}
  end

  def peek_back(%__MODULE__{size: 0}), do: :error

  def peek_back(%__MODULE__{capacity: cap, store: store, head: head, size: size}) do
    slot = rem(head + size - 1, cap)
    {:ok, :erlang.element(slot + 1, store)}
  end
end
```
