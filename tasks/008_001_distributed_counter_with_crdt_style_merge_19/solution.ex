  @doc """
  Returns the current integer value of the counter.

  Computed as `sum(p values) - sum(n values)` across all nodes.
  """
  @spec value(server()) :: integer()
  def value(server) do
    GenServer.call(server, :value)
  end