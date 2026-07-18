  @doc """
  Sets the flag's own state to `:on`, preserving its prerequisites.
  """
  @spec enable(atom()) :: :ok
  def enable(flag), do: GenServer.call(server(), {:set_state, flag, {:on}})