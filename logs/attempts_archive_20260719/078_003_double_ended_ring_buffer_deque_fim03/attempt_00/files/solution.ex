def to_list(%__MODULE__{size: 0}), do: []

def to_list(%__MODULE__{capacity: cap, store: store, head: head, size: size}) do
  Enum.map(0..(size - 1), fn offset ->
    :erlang.element(rem(head + offset, cap) + 1, store)
  end)
end