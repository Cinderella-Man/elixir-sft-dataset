  @impl true
  def handle_call({:set_state, flag, new_state}, _from, %{table: table} = state) do
    prereqs = existing_prereqs(table, flag)
    :ets.insert(table, {flag, new_state, prereqs})
    {:reply, :ok, state}
  end

  def handle_call({:set_prereqs, flag, prereqs}, _from, %{table: table} = state) do
    reply =
      if Enum.any?(prereqs, fn p -> reaches?(table, p, flag, MapSet.new()) end) do
        {:error, :cycle}
      else
        cur_state = existing_state(table, flag)
        :ets.insert(table, {flag, cur_state, prereqs})
        :ok
      end

    {:reply, reply, state}
  end