  @doc """
  Removes a registered job.

  Returns `:ok` or `{:error, :not_found}`.
  """
  @spec unregister(server(), job_name()) :: :ok | {:error, :not_found}
  def unregister(server, name) do
    GenServer.call(server, {:unregister, name})
  end