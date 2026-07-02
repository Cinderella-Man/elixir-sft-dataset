  test "a connection is retired after max_uses and replaced" do
    {_counter, create} = counting_create()
    {destroy, destroyed} = destroy_tracker()

    start_supervised!(
      {RecyclingPool, name: :rp_recycle, max_size: 1, max_uses: 2, create: create, destroy: destroy}
    )

    assert {:ok, c0} = RecyclingPool.checkout(:rp_recycle, 100)
    assert c0 == {:conn, 0}
    assert :ok = RecyclingPool.checkin(:rp_recycle, c0)

    # Second use of c0.
    assert {:ok, ^c0} = RecyclingPool.checkout(:rp_recycle, 100)
    assert :ok = RecyclingPool.checkin(:rp_recycle, c0)

    # c0 has now been used twice (max_uses): it is retired and replaced.
    assert destroyed.() == [c0]
    assert {:ok, c1} = RecyclingPool.checkout(:rp_recycle, 100)
    assert c1 != c0
    assert c1 == {:conn, 1}

    s = RecyclingPool.stats(:rp_recycle)
    assert s.total == 1
  end