  @doc "Removes and returns the front item, or `:empty`."
  @spec pop_front(t()) :: {:ok, any(), t()} | :empty
  def pop_front(%__MODULE__{size: 0}), do: :empty

  def pop_front(%__MODULE__{capacity: cap, store: store, head: head, size: size} = d) do
    item = :erlang.element(head + 1, store)
    {:ok, item, %{d | head: rem(head + 1, cap), size: size - 1}}
  end