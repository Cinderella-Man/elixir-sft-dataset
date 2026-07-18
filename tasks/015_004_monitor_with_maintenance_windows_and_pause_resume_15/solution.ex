  @spec schedule_check(service_name(), pos_integer()) :: reference()
  # Cancel a service's pending maintenance-expiry timer AND drain an
  # already-queued {:maintenance_end, name} for it. Cancelling alone is not
  # enough: a timer that fired before the cancel has its message queued BEHIND
  # the current call, and it would end the wrong (newer) maintenance session
  # (`after 0` cannot block: the message is either queued by now or was never
  # sent — the same argument as deregister's drain).
  @spec cancel_maintenance_timer(service(), service_name()) :: service()
  defp cancel_maintenance_timer(%{maintenance_timer: nil} = service, _name), do: service

  defp cancel_maintenance_timer(%{maintenance_timer: timer} = service, name) do
    Process.cancel_timer(timer)

    receive do
      {:maintenance_end, ^name} -> :ok
    after
      0 -> :ok
    end

    %{service | maintenance_timer: nil}
  end