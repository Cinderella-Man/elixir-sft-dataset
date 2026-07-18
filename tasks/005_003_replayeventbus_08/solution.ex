  @spec history(GenServer.server(), String.t()) :: [term()]
  def history(server, topic) when is_binary(topic) do
    GenServer.call(server, {:history, topic})
  end