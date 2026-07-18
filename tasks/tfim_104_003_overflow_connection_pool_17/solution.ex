  test "an overflow connection is dismissed cleanly without a :destroy option" do
    start_supervised!({OverflowPool, name: :op_no_destroy, size: 1, max_overflow: 1})

    assert {:ok, c1} = OverflowPool.checkout(:op_no_destroy, 100)
    assert {:ok, c2} = OverflowPool.checkout(:op_no_destroy, 100)

    # With the default no-op destroy the pool still shrinks back toward :size.
    assert :ok = OverflowPool.checkin(:op_no_destroy, c2)
    s = OverflowPool.stats(:op_no_destroy)
    assert s.total == 1 and s.overflow == 0 and s.in_use == 1 and s.available == 0

    assert :ok = OverflowPool.checkin(:op_no_destroy, c1)
    assert {:ok, ^c1} = OverflowPool.checkout(:op_no_destroy, 100)
  end