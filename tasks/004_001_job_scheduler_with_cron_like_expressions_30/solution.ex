  @doc """
  Returns a list of `{name, cron_expression, next_run}` tuples for every
  registered job.
  """
  @spec jobs(server()) :: [job_entry()]
  def jobs(server) do
    GenServer.call(server, :jobs)
  end