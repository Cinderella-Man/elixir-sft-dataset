def to_list(%__MODULE__{size: 0}), do: []

def to_list(%__MODULE__{capacity: cap, store: store, read: read, size: size}) do
  Enum.map(0..(size - 1), fn offset ->
    :erlang.element(rem(read + offset, cap) + 1, store)
  end)
end