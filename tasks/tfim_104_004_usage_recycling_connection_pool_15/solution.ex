  test "a waiter that dies while blocked is not handed a connection" do
    start_supervised!({RecyclingPool, name: :rp_dead_waiter, max_size: 1})

    assert {:ok, c} = RecyclingPool.checkout(:rp_dead_waiter, 2_000)

    waiter = spawn(fn -> RecyclingPool.checkout(:rp_dead_waiter, 5_000) end)
    Process.sleep(50)
    Process.exit(waiter, :kill)
    Process.sleep(50)

    assert :ok = RecyclingPool.checkin(:rp_dead_waiter, c)

    s = RecyclingPool.stats(:rp_dead_waiter)
    assert s.available == 1
    assert s.in_use == 0
    assert s.total == 1

    assert {:ok, ^c} = RecyclingPool.checkout(:rp_dead_waiter, 0)
  end