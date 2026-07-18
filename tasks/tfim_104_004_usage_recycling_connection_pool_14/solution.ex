  test "a blocked checkout times out server-side and leaves the pool usable" do
    start_supervised!({RecyclingPool, name: :rp_block_timeout, max_size: 1})

    assert {:ok, c} = RecyclingPool.checkout(:rp_block_timeout, 2_000)
    assert {:error, :timeout} = RecyclingPool.checkout(:rp_block_timeout, 100)

    s = RecyclingPool.stats(:rp_block_timeout)
    assert s.total == 1
    assert s.in_use == 1
    assert s.available == 0

    # The timed-out waiter is gone: a returned connection becomes available again.
    assert :ok = RecyclingPool.checkin(:rp_block_timeout, c)
    assert %{available: 1, in_use: 0} = RecyclingPool.stats(:rp_block_timeout)
    assert {:ok, ^c} = RecyclingPool.checkout(:rp_block_timeout, 0)
  end