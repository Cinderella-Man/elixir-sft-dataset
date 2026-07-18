  @doc """
  Sets the flag's own state to `:off`, preserving its prerequisites.
  """
  @spec disable(atom()) :: :ok
  def disable(flag), do: GenServer.call(server(), {:set_state, flag, {:off}})