  @impl true
  def handle_call({:submit, task_id, depends_on, func}, _from, state) do
    tasks = Map.put(state.tasks, task_id, %{depends_on: depends_on, func: func})
    {:reply, :ok, %{state | tasks: tasks}}
  end

  def handle_call(:run_all, _from, state) do
    tasks = state.tasks

    result =
      with :ok <- check_unknown_dependencies(tasks),
           :ok <- ensure_acyclic(tasks) do
        {:ok, schedule(tasks, state.max)}
      end

    {:reply, result, state}
  end