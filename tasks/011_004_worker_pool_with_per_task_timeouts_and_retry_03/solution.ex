  defp dispatch_to_worker(state, worker, task_info) do
    updated_task = %{task_info | attempts: task_info.attempts + 1}
    send(worker, {:run, {updated_task.ref, updated_task.client_pid, updated_task.func}})

    # Set a timer for task timeout. The message carries the task ref: a
    # timer that fired just as its task finished leaves a stale message in
    # the mailbox, and worker pids are reused — without the ref match the
    # stale timeout would kill whatever task the worker runs NEXT.
    timer_ref =
      Process.send_after(
        self(),
        {:task_timeout, worker, updated_task.ref},
        updated_task.task_timeout
      )

    %{
      state
      | busy_workers: Map.put(state.busy_workers, worker, updated_task),
        worker_timers: Map.put(state.worker_timers, worker, timer_ref)
    }
  end