  test "an overflow connection returned with no waiter is destroyed" do
    {_counter, create} = counting_create()
    {destroy, destroyed} = destroy_tracker()

    start_supervised!(
      {OverflowPool, name: :op_eph, size: 1, max_overflow: 1, create: create, destroy: destroy}
    )

    assert {:ok, _c1} = OverflowPool.checkout(:op_eph, 100)
    assert {:ok, c2} = OverflowPool.checkout(:op_eph, 100)

    # c2 is overflow; returning it with c1 still in use and no waiter destroys it.
    assert :ok = OverflowPool.checkin(:op_eph, c2)
    assert destroyed.() == [c2]

    s = OverflowPool.stats(:op_eph)
    assert s.total == 1 and s.overflow == 0 and s.available == 0 and s.in_use == 1
  end