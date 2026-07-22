  # One chain per service, always: cancel whatever is armed before arming the
  # successor, so a manual {:check, name} reschedules the cadence instead of
  # spawning a second timer chain alongside the periodic one.
  @spec rearm(service(), service_name()) :: service()
  defp rearm(service, name) do
    if service.check_timer, do: Process.cancel_timer(service.check_timer)
    %{service | check_timer: schedule_check(name, service.interval_ms)}
  end