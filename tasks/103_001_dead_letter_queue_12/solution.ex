  def purge(server, queue_name, older_than)
      when is_integer(older_than) do
    GenServer.call(server, {:purge, queue_name, older_than})
  end