  def run_all(name) do
    GenServer.call(name, :run_all, :infinity)
  end