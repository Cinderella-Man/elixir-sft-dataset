defmodule RingDeque do
  @moduledoc """
  A fixed-size, double-ended ring buffer (bounded deque) as a pure data
  structure.

  Items may be pushed/popped at either end in O(1). When the deque is full,
  pushing to one end silently overwrites (drops) the element at the OPPOSITE
  end: `push_back/2` drops the front, `push_front/2` drops the back.

  Internally, items live in a fixed-size tuple pre-allocated to `capacity`
  slots. A single integer `head` marks the front position and `size` tracks
  the live count. The back slot is always `rem(head + size - 1, capacity)`
  and the next back write goes to `rem(head + size, capacity)`; `head` moves
  backwards (with wraparound) for front pushes. All indices advance with
  `rem/2`, so every operation wraps around the tuple automatically.
  """

  @enforce_keys [:capacity, :store, :head, :size]
  defstruct [:capacity, :store, :head, :size]

  @type t :: %__MODULE__{
          capacity: pos_integer(),
          store: tuple(),
          head: non_neg_integer(),
          size: non_neg_integer()
        }

  @doc "Creates a new empty deque with the given fixed `capacity`."
  @spec new(pos_integer()) :: t()
  def new(capacity) when is_integer(capacity) and capacity > 0 do
    %__MODULE__{
      capacity: capacity,
      store: :erlang.make_tuple(capacity, nil),
      head: 0,
      size: 0
    }
  end

  @doc """
  Appends `item` at the back.

  When full, the current front is overwritten (dropped) so `size` stays at
  `capacity`.
  """
  @spec push_back(t(), any()) :: t()
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

  @doc """
  Prepends `item` at the front.

  When full, the current back is overwritten (dropped) so `size` stays at
  `capacity`.
  """
  @spec push_front(t(), any()) :: t()
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

  @doc "Removes and returns the front item, or `:empty`."
  @spec pop_front(t()) :: {:ok, any(), t()} | :empty
  def pop_front(%__MODULE__{size: 0}), do: :empty

  def pop_front(%__MODULE__{capacity: cap, store: store, head: head, size: size} = d) do
    item = :erlang.element(head + 1, store)
    {:ok, item, %{d | head: rem(head + 1, cap), size: size - 1}}
  end

  @doc "Removes and returns the back item, or `:empty`."
  @spec pop_back(t()) :: {:ok, any(), t()} | :empty
  def pop_back(%__MODULE__{size: 0}), do: :empty

  def pop_back(%__MODULE__{capacity: cap, store: store, head: head, size: size} = d) do
    slot = rem(head + size - 1, cap)
    item = :erlang.element(slot + 1, store)
    {:ok, item, %{d | size: size - 1}}
  end

  @doc "Returns all live items from front to back."
  @spec to_list(t()) :: list()
  def to_list(%__MODULE__{size: 0}), do: []

  def to_list(%__MODULE__{capacity: cap, store: store, head: head, size: size}) do
    Enum.map(0..(size - 1), fn offset ->
      :erlang.element(rem(head + offset, cap) + 1, store)
    end)
  end

  @doc "Returns the number of items currently stored (0..capacity)."
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{size: size}), do: size

  @doc "Returns `{:ok, item}` for the front item, or `:error` if empty."
  @spec peek_front(t()) :: {:ok, any()} | :error
  def peek_front(%__MODULE__{size: 0}), do: :error

  def peek_front(%__MODULE__{store: store, head: head}) do
    {:ok, :erlang.element(head + 1, store)}
  end

  @doc "Returns `{:ok, item}` for the back item, or `:error` if empty."
  @spec peek_back(t()) :: {:ok, any()} | :error
  def peek_back(%__MODULE__{size: 0}), do: :error

  def peek_back(%__MODULE__{capacity: cap, store: store, head: head, size: size}) do
    slot = rem(head + size - 1, cap)
    {:ok, :erlang.element(slot + 1, store)}
  end
end
