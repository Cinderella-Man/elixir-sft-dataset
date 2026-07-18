  @spec subscribers(GenServer.server(), String.t()) :: [{reference(), pid(), integer()}]
  def subscribers(server, topic) when is_binary(topic) do
    GenServer.call(server, {:subscribers, topic})
  end