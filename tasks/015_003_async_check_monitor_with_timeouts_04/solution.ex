@impl GenServer
def handle_call({:register, name, check_func, interval_ms, opts}, _from, state) do
  if Map.has_key?(state.services, name) do
    {:reply, {:error, :already_registered}, state}
  else
    max_failures = Keyword.get(opts, :max_failures, 3)
    timeout_ms = Keyword.get(opts, :timeout_ms, 5_000)

    service = %{
      check_func: check_func,
      interval_ms: interval_ms,
      max_failures: max_failures,
      timeout_ms: timeout_ms,
      status: :pending,
      last_check_at: nil,
      consecutive_failures: 0,
      notified_down: false,
      task_ref: nil,
      task_pid: nil
    }

    schedule_check(name, interval_ms)

    {:reply, :ok, put_in(state.services[name], service)}
  end
end

def handle_call({:status, name}, _from, state) do
  case Map.fetch(state.services, name) do
    {:ok, service} -> {:reply, {:ok, to_status_info(service)}, state}
    :error -> {:reply, {:error, :not_found}, state}
  end
end

def handle_call(:statuses, _from, state) do
  result = Map.new(state.services, fn {name, svc} -> {name, to_status_info(svc)} end)
  {:reply, result, state}
end

def handle_call({:deregister, name}, _from, state) do
  case Map.fetch(state.services, name) do
    {:ok, service} ->
      # Kill any in-flight task.
      if service.task_pid do
        Process.exit(service.task_pid, :kill)
      end

      {:reply, :ok, %{state | services: Map.delete(state.services, name)}}

    :error ->
      {:reply, :ok, state}
  end
end