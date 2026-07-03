  test "in_flight_count reflects pending work", %{pid: pid} do
    parent = self()

    spawn(fn ->
      send(parent, {:done, CoalescingPayments.process_payment(pid, @valid, "slow")})
    end)

    Process.sleep(50)
    assert CoalescingPayments.in_flight_count(pid) == 1

    assert_receive {:done, {:ok, _}}, 2000
    assert CoalescingPayments.in_flight_count(pid) == 0
  end