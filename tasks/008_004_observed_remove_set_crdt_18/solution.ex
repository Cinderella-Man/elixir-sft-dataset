  @doc """
  Returns `true` if `element` is currently in the set, `false` otherwise.
  """
  @spec member?(server(), element()) :: boolean()
  def member?(server, element) do
    GenServer.call(server, {:member?, element})
  end