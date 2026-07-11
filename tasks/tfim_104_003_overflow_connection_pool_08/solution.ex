  test "distinct connections" do
    start_supervised!({OverflowPool, name: :op_distinct, size: 2, max_overflow: 0})
    assert {:ok, c1} = OverflowPool.checkout(:op_distinct, 100)
    assert {:ok, c2} = OverflowPool.checkout(:op_distinct, 100)
    assert c1 != c2
  end