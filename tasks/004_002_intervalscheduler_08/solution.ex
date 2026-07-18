  @spec next_run(GenServer.server(), term()) :: {:ok, NaiveDateTime.t()} | {:error, :not_found}
  def next_run(server, job_name), do: GenServer.call(server, {:next_run, job_name})