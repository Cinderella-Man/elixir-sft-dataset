  # Base case: nothing running and nothing queued.
  defp collect(running, [] = _queue, _func, results, pids) when map_size(running) == 0,
    do: {results, pids}

  # The as-they-finish loop: harvest whatever `Task.yield_many/2` reports in
  # this tick — a normal reply (`{:ok, value}`) or a crash (`{:exit, reason}`,
  # covering raises, abnormal exits, throws and external kills alike) — then
  # refill the freed slots from the queue and go again.
  defp collect(running, queue, func, results, pids) do
    finished =
      running
      |> Map.keys()
      |> Task.yield_many(20)
      |> Enum.filter(fn {_task, res} -> res != nil end)

    case finished do
      [] ->
        collect(running, queue, func, results, pids)

      finished ->
        finished
        |> Enum.reduce({running, queue, results, pids}, fn {task, res}, {run, q, acc, ps} ->
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
              {run, [], acc, ps}

            [{elem, next_idx} | rest] ->
              refill = start_task(func, elem)
              {Map.put(run, refill, next_idx), rest, acc, Map.put(ps, refill.pid, true)}
          end
        end)
        |> then(fn {run, q, acc, ps} -> collect(run, q, func, acc, ps) end)
    end
  end