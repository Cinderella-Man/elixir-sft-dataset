  @spec peek(server()) :: {:ok, term(), non_neg_integer()} | :empty
  def peek(server) do
    GenServer.call(server, :peek)
  end