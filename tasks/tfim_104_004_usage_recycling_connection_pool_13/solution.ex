  test "timeout 0 is accepted: it serves when possible and errors when exhausted" do
    start_supervised!({RecyclingPool, name: :rp_zero, max_size: 1})

    # A zero timeout still creates/serves a connection when one can be had.
    assert {:ok, c} = RecyclingPool.checkout(:rp_zero, 0)
    # At max_size with nothing available, a zero timeout errors immediately.
    assert {:error, :timeout} = RecyclingPool.checkout(:rp_zero, 0)

    assert :ok = RecyclingPool.checkin(:rp_zero, c)
    assert {:ok, ^c} = RecyclingPool.checkout(:rp_zero, 0)
  end