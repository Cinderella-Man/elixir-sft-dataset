  @doc "Returns the number of items currently buffered for `key` (0 if none)."
  @spec pending(term()) :: non_neg_integer()
  def pending(key), do: GenServer.call(__MODULE__, {:pending, key})