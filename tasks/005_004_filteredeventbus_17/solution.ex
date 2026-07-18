  def subscribe(server, topic, pid, filter \\ [])
      when is_binary(topic) and is_pid(pid) and is_list(filter) do
    if valid_filter?(filter) do
      GenServer.call(server, {:subscribe, topic, pid, filter})
    else
      {:error, :invalid_filter}
    end
  end