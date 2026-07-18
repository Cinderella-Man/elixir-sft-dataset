  @doc """
  Returns `{:ok, item}` for the oldest (first-inserted) live item,
  or `:error` if the buffer is empty.

  ## Examples

      iex> RingBuffer.new(3) |> RingBuffer.push(:a)
      ...> |> RingBuffer.push(:b) |> RingBuffer.peek_oldest()
      {:ok, :a}

      iex> RingBuffer.new(3) |> RingBuffer.peek_oldest()
      :error
  """
  @spec peek_oldest(t()) :: {:ok, any()} | :error
  def peek_oldest(%__MODULE__{size: 0}), do: :error

  def peek_oldest(%__MODULE__{store: store, read: read}) do
    {:ok, :erlang.element(read + 1, store)}
  end