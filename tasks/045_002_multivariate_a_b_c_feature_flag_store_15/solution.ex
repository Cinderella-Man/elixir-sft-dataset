  @impl true
  def handle_call({:set, flag_name, value}, _from, %{table: table} = state) do
    :ets.insert(table, {flag_name, value})
    {:reply, :ok, state}
  end