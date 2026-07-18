  @impl true
  def handle_call({:submit, task_func, opts}, {from_pid, _}, state) do
    ref = make_ref()
    task_timeout = Keyword.get(opts, :task_timeout, 30_000)
    max_retries = Keyword.get(opts, :max_retries, 0)

    task_info = %TaskInfo{
      ref: ref,
      client_pid: from_pid,
      func: task_func,
      task_timeout: task_timeout,
      max_retries: max_retries,
      attempts: 0
    }

    cond do
      length(state.idle_workers) > 0 ->
        [worker | rest] = state.idle_workers
        new_state = dispatch_to_worker(%{state | idle_workers: rest}, worker, task_info)
        {:reply, {:ok, ref}, new_state}

      :queue.len(state.queue) < state.max_queue ->
        new_state = %{state | queue: :queue.in(task_info, state.queue)}
        {:reply, {:ok, ref}, new_state}

      true ->
        {:reply, {:error, :queue_full}, state}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      busy_workers: map_size(state.busy_workers),
      idle_workers: length(state.idle_workers),
      queue_length: :queue.len(state.queue),
      retry_count: state.retry_count
    }

    {:reply, status, state}
  end