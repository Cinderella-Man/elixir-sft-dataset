  test "creates overflow up to size + max_overflow, then times out" do
    start_supervised!({OverflowPool, name: :op_grow, size: 1, max_overflow: 1})
    assert {:ok, _c1} = OverflowPool.checkout(:op_grow, 100)
    assert {:ok, _c2} = OverflowPool.checkout(:op_grow, 100)

    s = OverflowPool.stats(:op_grow)
    assert s.total == 2 and s.overflow == 1

    assert {:error, :timeout} = OverflowPool.checkout(:op_grow, 50)
  end