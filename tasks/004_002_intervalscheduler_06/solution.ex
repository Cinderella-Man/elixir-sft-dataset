  @spec unregister(GenServer.server(), term()) :: :ok | {:error, :not_found}
  def unregister(server, job_name) do
    GenServer.call(server, {:unregister, job_name})
  end