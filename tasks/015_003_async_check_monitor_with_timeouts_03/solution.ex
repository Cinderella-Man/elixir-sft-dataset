@impl GenServer
def handle_info({:schedule_check, name}, state) do
  case Map.fetch(state.services, name) do
    :error ->
      {:noreply, state}

    {:ok, service} ->
      # Spawn a Task to run the check function.
      gen_server = self()
      ref = make_ref()

      {:ok, pid} =
        Task.start(fn ->
          result =
            try do
              service.check_func.()
            rescue
              e -> {:error, {:exception, Exception.message(e)}}
            catch
              kind, value -> {:error, {kind, value}}
            end

          send(gen_server, {:check_result, name, ref, result})
        end)

      # Monitor the task so we know if it crashes.
      Process.monitor(pid)

      # Schedule a timeout message.
      Process.send_after(self(), {:check_timeout, name, ref}, service.timeout_ms)

      new_service = %{service | task_ref: ref, task_pid: pid}
      {:noreply, put_in(state.services[name], new_service)}
  end
end

def handle_info({:check_result, name, ref, result}, state) do
  case Map.fetch(state.services, name) do
    :error ->
      {:noreply, state}

    {:ok, %{task_ref: ^ref} = service} ->
      now = state.clock.()
      {new_service, notify?} = apply_check_result(service, result, now)
      new_service = %{new_service | task_ref: nil, task_pid: nil}

      schedule_check(name, service.interval_ms)

      new_state = put_in(state.services[name], new_service)

      if notify? do
        {:error, reason} = result
        fire_notify(state.notify, name, reason)
      end

      {:noreply, new_state}

    {:ok, _service} ->
      # Stale ref — result from an old task. Discard.
      {:noreply, state}
  end
end

def handle_info({:check_timeout, name, ref}, state) do
  case Map.fetch(state.services, name) do
    :error ->
      {:noreply, state}

    {:ok, %{task_ref: ^ref, task_pid: pid} = service} ->
      # Kill the timed-out task.
      if pid, do: Process.exit(pid, :kill)

      now = state.clock.()
      {new_service, notify?} = apply_check_result(service, {:error, :timeout}, now)
      new_service = %{new_service | task_ref: nil, task_pid: nil}

      schedule_check(name, service.interval_ms)

      new_state = put_in(state.services[name], new_service)

      if notify? do
        fire_notify(state.notify, name, :timeout)
      end

      {:noreply, new_state}

    {:ok, _service} ->
      # Stale ref — timeout for an already-completed or replaced task.
      {:noreply, state}
  end
end

# Handle DOWN messages from monitored tasks — just ignore them.
# We handle lifecycle via check_result/check_timeout.
def handle_info({:DOWN, _monitor_ref, :process, _pid, _reason}, state) do
  {:noreply, state}
end

def handle_info(_msg, state), do: {:noreply, state}