defp execute(layers, tasks) do
  Enum.reduce(layers, %{}, fn layer, results ->
    layer_results =
      layer
      |> Enum.map(fn id ->
        %{depends_on: deps, func: func} = Map.fetch!(tasks, id)
        inputs = Map.new(deps, fn d -> {d, Map.fetch!(results, d)} end)
        {id, Task.async(fn -> func.(inputs) end)}
      end)
      |> Enum.map(fn {id, task} -> {id, Task.await(task, :infinity)} end)
      |> Map.new()

    Map.merge(results, layer_results)
  end)
end