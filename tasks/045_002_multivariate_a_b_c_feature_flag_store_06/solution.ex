  @doc "Enables `flag_name` globally (`:on`)."
  @spec enable(atom()) :: :ok
  def enable(flag_name), do: GenServer.call(server(), {:set, flag_name, {:on}})