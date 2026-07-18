  @doc "Disables `flag_name` globally (`:off`)."
  @spec disable(atom()) :: :ok
  def disable(flag_name), do: GenServer.call(server(), {:set, flag_name, {:off}})