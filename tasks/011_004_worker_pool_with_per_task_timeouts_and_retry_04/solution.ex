defp make_worker_available(state, worker) do
  case :queue.out(state.queue) do
    {{:value, task_info}, remaining_queue} ->
      dispatch_to_worker(%{state | queue: remaining_queue}, worker, task_info)

    {:empty, _} ->
      %{
        state
        | idle_workers: [worker | state.idle_workers],
          busy_workers: Map.delete(state.busy_workers, worker)
      }
  end
end