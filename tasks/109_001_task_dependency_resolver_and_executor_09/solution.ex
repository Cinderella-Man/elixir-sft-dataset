  @impl true
  def handle_call({:submit, task_id, depends_on, func}, _from, tasks) do
    tasks = Map.put(tasks, task_id, %{depends_on: depends_on, func: func})
    {:reply, :ok, tasks}
  end

  @impl true
  def handle_call(:run_all, _from, tasks) do
    result =
      with :ok <- check_unknown_dependencies(tasks),
           {:ok, layers} <- topological_layers(tasks) do
        {:ok, execute(layers, tasks)}
      end

    {:reply, result, tasks}
  end