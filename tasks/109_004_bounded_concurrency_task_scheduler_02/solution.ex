  defp loop(s) do
    running_count = map_size(s.running)

    cond do
      s.ready != [] and running_count < s.max ->
        [id | rest] = s.ready
        %{func: func} = Map.fetch!(s.tasks, id)
        task = Task.async(fn -> func.() end)
        loop(%{s | ready: rest, running: Map.put(s.running, task.ref, id)})

      running_count == 0 and s.ready == [] ->
        s.results

      true ->
        loop(await_one(s))
    end
  end