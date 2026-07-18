  @doc """
  Returns `true` if `element` is currently in the set, `false` otherwise.

  An element is present when its add timestamp is strictly greater than its
  remove timestamp. If the timestamps are equal (tie), the element is
  considered absent (remove-wins bias).
  """
  @spec member?(server(), element()) :: boolean()
  def member?(server, element) do
    GenServer.call(server, {:member?, element})
  end