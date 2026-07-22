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