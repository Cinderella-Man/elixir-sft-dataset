  # Base case: nothing running and nothing queued.
  defp collect(running, [] = _queue, _func, results) when map_size(running) == 0,
    do: results

  # The as-they-finish loop: harvest whatever `Task.yield_many/2` reports in
  # this tick — a normal reply (`{:ok, value}`) or a crash (`{:exit, reason}`,
  # covering raises, abnormal exits, throws and external kills alike) — then
  # refill the freed slots from the queue and go again.
  defp collect(running, queue, func, results) do
    finished =
      running
      |> Map.keys()
      |> Task.yield_many(20)
      |> Enum.filter(fn {_task, res} -> res != nil end)

    case finished do
      [] ->
        collect(running, queue, func, results)

      finished ->
        Enum.reduce(finished, {running, queue, results}, fn {task, res}, {run, q, acc} ->
          idx = Map.fetch!(run, task)

          outcome =
            case res do
              {:ok, value} -> value
              {:exit, reason} -> {:error, reason}
            end

          run = Map.delete(run, task)
          acc = Map.put(acc, idx, outcome)

          case q do
            [] ->
              {run, [], acc}

            [{elem, next_idx} | rest] ->
              {Map.put(run, start_task(func, elem), next_idx), rest, acc}
          end
        end)
        |> then(fn {run, q, acc} -> collect(run, q, func, acc) end)
    end
  end
