  test "the default connection factory hands out fresh distinct references" do
    start_supervised!({OverflowPool, name: :op_def_create, size: 1, max_overflow: 1})

    assert {:ok, c1} = OverflowPool.checkout(:op_def_create, 100)
    assert {:ok, c2} = OverflowPool.checkout(:op_def_create, 100)

    assert is_reference(c1) and is_reference(c2)
    assert c1 != c2
  end