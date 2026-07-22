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