  @doc "Rewinds the cursor to the beginning of the script."
  @spec reset(GenServer.server()) :: :ok
  def reset(server), do: GenServer.call(server, :reset)