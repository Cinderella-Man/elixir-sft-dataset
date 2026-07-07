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