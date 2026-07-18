  @doc "Returns `{:ok, item}` for the front item, or `:error` if empty."
  @spec peek_front(t()) :: {:ok, any()} | :error
  def peek_front(%__MODULE__{size: 0}), do: :error

  def peek_front(%__MODULE__{store: store, head: head}) do
    {:ok, :erlang.element(head + 1, store)}
  end