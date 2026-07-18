  @spec cancel(GenServer.server(), term()) :: :ok | {:error, :not_found}
  def cancel(server, job_name), do: GenServer.call(server, {:cancel, job_name})