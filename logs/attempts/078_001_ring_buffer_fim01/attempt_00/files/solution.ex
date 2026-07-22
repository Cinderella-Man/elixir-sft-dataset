  def push(%__MODULE__{} = buf, item) do
    %{capacity: cap, store: store, read: read, write: write, size: size} = buf

    # Write the item into the current write slot.
    new_store = :erlang.setelement(write + 1, store, item)
    new_write = rem(write + 1, cap)

    # If the buffer was already full, the write head just trampled the oldest
    # slot, so we must advance the read head to keep it pointing at the new
    # oldest item.  size stays at `cap`.
    if size == cap do
      %{buf | store: new_store, write: new_write, read: rem(read + 1, cap)}
    else
      %{buf | store: new_store, write: new_write, size: size + 1}
    end
  end