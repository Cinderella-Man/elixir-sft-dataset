  @doc """
  Deregisters a service and cancels any pending check for it.

  Always returns `:ok`, even if the service was not registered.
  """
  @spec deregister(GenServer.server(), service_name()) :: :ok
  def deregister(server, service_name) do
    GenServer.call(server, {:deregister, service_name})
  end