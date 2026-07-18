  @spec jobs(GenServer.server()) :: [{term(), tuple(), NaiveDateTime.t()}]
  def jobs(server), do: GenServer.call(server, :jobs)