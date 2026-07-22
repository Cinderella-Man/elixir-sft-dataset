  def handle_call({:set_password, username, password}, _from, state) do
    history = Map.get(state.users, username, [])

    case violations(password, username, history, state.policy) do
      [] ->
        new_history = Enum.take([password | history], state.history_size)
        users = Map.put(state.users, username, new_history)
        {:reply, :ok, %{state | users: users}}

      list ->
        {:reply, {:error, list}, state}
    end
  end

  def handle_call({:history_count, username}, _from, state) do
    {:reply, length(Map.get(state.users, username, [])), state}
  end