  test "a waiter that already timed out is never served by a later checkin" do
    start_supervised!({OverflowPool, name: :op_stale, size: 1, max_overflow: 0})
    parent = self()

    assert {:ok, c1} = OverflowPool.checkout(:op_stale, 100)

    spawn(fn -> send(parent, {:done, OverflowPool.checkout(:op_stale, 100)}) end)
    assert_receive {:done, {:error, :timeout}}, 1_000

    # The waiter has retired: the returned connection must go back to the pool,
    # not to the caller that already got its timeout result.
    assert :ok = OverflowPool.checkin(:op_stale, c1)
    refute_receive {:done, _}, 200

    s = OverflowPool.stats(:op_stale)
    assert s.total == 1 and s.available == 1 and s.in_use == 0

    assert {:ok, ^c1} = OverflowPool.checkout(:op_stale, 100)
  end