  @doc "Current total resident weight."
  @spec weight(name()) :: non_neg_integer()
  def weight(name), do: GenServer.call(name, :weight)