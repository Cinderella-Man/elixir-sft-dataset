  @doc "Returns `{:ok, item}` for the back item, or `:error` if empty."
  @spec peek_back(t()) :: {:ok, any()} | :error
  def peek_back(%__MODULE__{size: 0}), do: :error

  def peek_back(%__MODULE__{capacity: cap, store: store, head: head, size: size}) do
    slot = rem(head + size - 1, cap)
    {:ok, :erlang.element(slot + 1, store)}
  end