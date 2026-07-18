  def next_run(server, name) do
    GenServer.call(server, {:next_run, name})
  end