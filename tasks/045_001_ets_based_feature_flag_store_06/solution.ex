  @doc "Enables `flag_name` for **all** users (`:on` state)."
  @spec enable(atom()) :: :ok
  def enable(flag_name) do
    GenServer.call(server(), {:set, flag_name, {:on}})
  end