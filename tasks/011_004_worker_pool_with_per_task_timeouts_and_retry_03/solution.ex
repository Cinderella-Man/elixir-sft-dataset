  defp dispatch_to_worker(state, worker, task_info) do
    updated_task = %{task_info | attempts: task_info.attempts + 1}
    send(worker, {:run, {updated_task.ref, updated_task.client_pid, updated_task.func}})

    # Set a timer for task timeout
    timer_ref = Process.send_after(self(), {:task_timeout, worker}, updated_task.task_timeout)

    %{
      state
      | busy_workers: Map.put(state.busy_workers, worker, updated_task),
        timers: Map.put(state.timers, timer_ref, worker),
        worker_timers: Map.put(state.worker_timers, worker, timer_ref)
    }
  end