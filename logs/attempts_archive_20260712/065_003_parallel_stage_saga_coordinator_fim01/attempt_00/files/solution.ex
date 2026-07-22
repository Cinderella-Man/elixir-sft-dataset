# `completed` holds step maps in reverse completion order (most recent first).
defp run_stages([], _idx, context, _completed), do: {:ok, context}

defp run_stages([stage | rest], idx, context, completed) do
  results =
    stage
    |> Enum.map(fn step -> {step, Task.async(fn -> step.action.(context) end)} end)
    |> Enum.map(fn {step, task} -> {step, Task.await(task, @await_timeout)} end)

  failures = for {step, {:error, reason}} <- results, into: %{}, do: {step.name, reason}

  if map_size(failures) == 0 do
    new_context =
      Enum.reduce(results, context, fn {step, {:ok, result}}, acc ->
        Map.put(acc, step.name, result)
      end)

    succeeded = Enum.map(results, fn {step, _} -> step end)
    run_stages(rest, idx + 1, new_context, Enum.reverse(succeeded) ++ completed)
  else
    succeeded = for {step, {:ok, _}} <- results, do: step

    comp_context =
      Enum.reduce(results, context, fn
        {step, {:ok, result}}, acc -> Map.put(acc, step.name, result)
        {_step, {:error, _}}, acc -> acc
      end)

    to_compensate = Enum.reverse(succeeded) ++ completed
    compensate(to_compensate, comp_context, idx, failures)
  end
end