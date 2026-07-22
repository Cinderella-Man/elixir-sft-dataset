  defp cancel_task_timer(state, worker_pid) do
    case Map.pop(state.worker_timers, worker_pid) do
      {nil, _} ->
        state

      {timer_ref, new_worker_timers} ->
        Process.cancel_timer(timer_ref)
        %{state | worker_timers: new_worker_timers}
    end
  end