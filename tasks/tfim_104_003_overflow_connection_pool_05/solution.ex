  test "a base connection returned with no waiter is kept available" do
    {destroy, destroyed} = destroy_tracker()

    start_supervised!({OverflowPool, name: :op_base, size: 2, max_overflow: 0, destroy: destroy})

    assert {:ok, c1} = OverflowPool.checkout(:op_base, 100)
    assert {:ok, _c2} = OverflowPool.checkout(:op_base, 100)
    assert :ok = OverflowPool.checkin(:op_base, c1)

    assert destroyed.() == []
    assert {:ok, ^c1} = OverflowPool.checkout(:op_base, 100)
  end