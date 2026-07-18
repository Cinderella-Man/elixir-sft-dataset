  @impl true
  def handle_call({:register, name, rule, mfa}, _from, state) do
    cond do
      Map.has_key?(state.jobs, name) ->
        {:reply, {:error, :already_exists}, state}

      not valid_rule?(rule) ->
        {:reply, {:error, :invalid_rule}, state}

      true ->
        now = state.clock.()
        job = %{mfa: mfa, rule: rule, next_run: compute_next_run(rule, now)}
        {:reply, :ok, %{state | jobs: Map.put(state.jobs, name, job)}}
    end
  end

  def handle_call({:unregister, name}, _from, state) do
    case Map.pop(state.jobs, name) do
      {nil, _} -> {:reply, {:error, :not_found}, state}
      {_, new_jobs} -> {:reply, :ok, %{state | jobs: new_jobs}}
    end
  end

  def handle_call(:jobs, _from, state) do
    list = Enum.map(state.jobs, fn {n, j} -> {n, j.rule, j.next_run} end)
    {:reply, list, state}
  end

  def handle_call({:next_run, name}, _from, state) do
    case Map.fetch(state.jobs, name) do
      {:ok, j} -> {:reply, {:ok, j.next_run}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end