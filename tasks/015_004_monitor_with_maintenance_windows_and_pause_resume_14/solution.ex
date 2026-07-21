  @impl GenServer
  def handle_call({:register, name, check_func, interval_ms, max_failures}, _from, state) do
    if Map.has_key?(state.services, name) do
      {:reply, {:error, :already_registered}, state}
    else
      service = %{
        check_func: check_func,
        interval_ms: interval_ms,
        max_failures: max_failures,
        health: :pending,
        mode: :active,
        last_check_at: nil,
        consecutive_failures: 0,
        notified_down: false,
        maintenance_ends_at: nil,
        maintenance_timer: nil,
        check_timer: nil
      }

      service = %{service | check_timer: schedule_check(name, interval_ms)}

      {:reply, :ok, put_in(state.services[name], service)}
    end
  end
