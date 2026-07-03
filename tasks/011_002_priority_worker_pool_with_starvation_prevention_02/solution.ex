  defp dispatch_next(state, worker) do
    case dequeue_highest(state.queues) do
      {:ok, {ref, client_pid, func, _enqueued_at}, new_queues} ->
        send(worker, {:run, {ref, client_pid, func}})

        %{
          state
          | queues: new_queues,
            busy_workers: Map.put(state.busy_workers, worker, {ref, client_pid})
        }

      :empty ->
        %{
          state
          | idle_workers: [worker | state.idle_workers],
            busy_workers: Map.delete(state.busy_workers, worker)
        }
    end
  end