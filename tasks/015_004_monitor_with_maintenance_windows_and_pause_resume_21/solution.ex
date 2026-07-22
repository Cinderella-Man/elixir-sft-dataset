  # One chain per service, always: cancel whatever is armed before arming the
  # next timer, so neither a manual {:check, name} trigger nor a stale chain
  # can multiply the check rate.
  defp rearm(service, name) do
    if service.check_timer, do: Process.cancel_timer(service.check_timer)
    %{service | check_timer: schedule_check(name, service.interval_ms)}
  end