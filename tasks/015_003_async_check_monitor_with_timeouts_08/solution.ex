  @spec statuses(GenServer.server()) :: %{service_name() => status_info()}
  def statuses(server) do
    GenServer.call(server, :statuses)
  end