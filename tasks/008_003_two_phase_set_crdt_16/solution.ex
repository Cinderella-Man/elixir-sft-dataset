  @doc """
  Returns `true` if `element` is currently in the set, `false` otherwise.

  An element is present when it is in the add-set but not the remove-set.
  """
  @spec member?(server(), element()) :: boolean()
  def member?(server, element) do
    GenServer.call(server, {:member?, element})
  end