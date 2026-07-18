  @doc """
  Returns the processing history as a list of `{task, result}` tuples.
  """
  @spec processed(server()) :: [{term(), term()}]
  def processed(server) do
    GenServer.call(server, :processed)
  end