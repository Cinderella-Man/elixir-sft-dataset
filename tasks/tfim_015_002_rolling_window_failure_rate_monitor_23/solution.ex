  test "registered checks run automatically on the periodic timer", %{mon: mon} do
    CheckFn.set_result("timer_svc", :ok)
    RateMonitor.register(mon, "timer_svc", CheckFn.build("timer_svc"), 25)

    # No manual {:check, _} is ever sent here; only the periodic timer can
    # advance the window, so observing a completed check proves scheduling.
    assert :ok =
             poll_until(
               fn ->
                 case RateMonitor.status(mon, "timer_svc") do
                   {:ok, %{checks_in_window: n}} -> n >= 1
                   _ -> false
                 end
               end,
               2_000
             )
  end