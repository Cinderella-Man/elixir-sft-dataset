  @spec subscribe(GenServer.server(), String.t(), pid(), integer()) :: {:ok, reference()}
  def subscribe(server, topic, pid, priority)
      when is_binary(topic) and is_pid(pid) and is_integer(priority) do
    GenServer.call(server, {:subscribe, topic, pid, priority})
  end