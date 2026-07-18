  @doc """
  Removes and returns the oldest item.

  Returns `{:ok, item, buffer}`, or `:empty` when the buffer holds nothing.
  """
  @spec pop(t()) :: {:ok, any(), t()} | :empty
  def pop(%__MODULE__{size: 0}), do: :empty

  def pop(%__MODULE__{capacity: cap, store: store, read: read, size: size} = buf) do
    item = :erlang.element(read + 1, store)
    {:ok, item, %{buf | read: rem(read + 1, cap), size: size - 1}}
  end