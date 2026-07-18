  @spec status(GenServer.server(), term()) ::
          {:ok, :pending | :completed | :dead, non_neg_integer()}
          | {:error, :not_found}
  def status(server, job_name), do: GenServer.call(server, {:status, job_name})