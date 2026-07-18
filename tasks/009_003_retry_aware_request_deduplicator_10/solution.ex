  @impl GenServer
  def handle_info({:task_result, key, result}, state) do
    case Map.fetch(state, key) do
      {:ok, entry} ->
        handle_attempt_result(key, entry, result, state)

      :error ->
        {:noreply, state}
    end
  end

  def handle_info({:retry_now, key}, state) do
    case Map.fetch(state, key) do
      {:ok, %{func: func} = entry} ->
        spawn_attempt(key, func)
        {:noreply, Map.put(state, key, %{entry | status: :running})}

      :error ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end