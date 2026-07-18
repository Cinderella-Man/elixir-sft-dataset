  @doc "Removes and returns the back item, or `:empty`."
  @spec pop_back(t()) :: {:ok, any(), t()} | :empty
  def pop_back(%__MODULE__{size: 0}), do: :empty

  def pop_back(%__MODULE__{capacity: cap, store: store, head: head, size: size} = d) do
    slot = rem(head + size - 1, cap)
    item = :erlang.element(slot + 1, store)
    {:ok, item, %{d | size: size - 1}}
  end