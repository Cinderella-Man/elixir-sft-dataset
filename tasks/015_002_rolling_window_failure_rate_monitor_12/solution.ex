  @impl GenServer
  def handle_info({:check, name}, state) do
    case Map.fetch(state.services, name) do
      :error ->
        # Service was deregistered; discard stale message.
        {:noreply, state}

      {:ok, service} ->
        now = state.clock.()
        result = service.check_func.()

        {new_service, notify?} = apply_check_result(service, result, now)

        schedule_check(name, service.interval_ms)

        new_state = put_in(state.services[name], new_service)

        if notify? do
          fire_notify(state.notify, name, compute_failure_rate(new_service.history))
        end

        {:noreply, new_state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}