  test "checkout with timeout 0 on a full pool returns {:error, :timeout}" do
    start_supervised!({OverflowPool, name: :op_zero, size: 1, max_overflow: 0})

    # Exhaust the pool: base is in use and no overflow is allowed.
    assert {:ok, _c1} = OverflowPool.checkout(:op_zero, 100)

    # A timeout of 0 is a valid, non-blocking checkout that yields the
    # timeout result as a normal value when nothing is available.
    assert {:error, :timeout} = OverflowPool.checkout(:op_zero, 0)

    # The failed checkout borrowed nothing: the pool is unchanged.
    s = OverflowPool.stats(:op_zero)
    assert s.total == 1 and s.in_use == 1 and s.available == 0 and s.overflow == 0
  end