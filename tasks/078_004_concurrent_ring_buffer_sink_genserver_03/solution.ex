defp do_to_list(%{size: 0}), do: []

defp do_to_list(%{capacity: cap, store: store, read: read, size: size}) do
  Enum.map(0..(size - 1), fn offset ->
    :erlang.element(rem(read + offset, cap) + 1, store)
  end)
end