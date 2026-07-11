  test "a crashed holder's connection is reclaimed" do
    start_supervised!({OverflowPool, name: :op_crash, size: 1, max_overflow: 0})
    {holder, {:ok, _conn}} = spawn_holder(:op_crash, 1_000)
    assert {:error, :timeout} = OverflowPool.checkout(:op_crash, 50)
    Process.exit(holder, :kill)
    assert {:ok, _reclaimed} = OverflowPool.checkout(:op_crash, 1_000)
  end