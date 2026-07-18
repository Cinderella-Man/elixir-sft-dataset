  @doc "Returns the list of `{task, result}` pairs in the order the tasks finished processing."
  @spec processed(server()) :: [{term(), term()}]
  def processed(server) do
    GenServer.call(server, :processed)
  end