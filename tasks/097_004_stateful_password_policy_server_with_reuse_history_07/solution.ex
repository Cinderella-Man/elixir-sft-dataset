  @spec history_count(GenServer.server(), String.t()) :: non_neg_integer()
  def history_count(server, username) do
    GenServer.call(server, {:history_count, username})
  end