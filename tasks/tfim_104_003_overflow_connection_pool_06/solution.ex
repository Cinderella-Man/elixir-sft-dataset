  test "an overflow connection handed to a waiter stays alive" do
    {destroy, destroyed} = destroy_tracker()

    start_supervised!({OverflowPool, name: :op_wait, size: 1, max_overflow: 1, destroy: destroy})

    {:ok, _c1} = OverflowPool.checkout(:op_wait, 100)
    {:ok, c2} = OverflowPool.checkout(:op_wait, 100)

    parent = self()

    # The waiter must stay alive after receiving its connection; otherwise the
    # pool's crash-reclamation would reclaim (and, as overflow, destroy) it.
    waiter =
      spawn(fn ->
        send(parent, {:result, OverflowPool.checkout(:op_wait, 1_000)})

        receive do
          :release -> :ok
        end
      end)

    Process.sleep(50)
    refute_received {:result, _}

    # A waiter exists, so returning the overflow connection hands it over alive.
    assert :ok = OverflowPool.checkin(:op_wait, c2)
    assert_receive {:result, {:ok, got}}, 1_000
    assert got == c2
    assert destroyed.() == []

    s = OverflowPool.stats(:op_wait)
    assert s.total == 2

    send(waiter, :release)
  end