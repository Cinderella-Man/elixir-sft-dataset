  test "a not-yet-exhausted connection is reused" do
    {_counter, create} = counting_create()
    {destroy, destroyed} = destroy_tracker()

    start_supervised!(
      {RecyclingPool, name: :rp_reuse, max_size: 1, max_uses: 3, create: create, destroy: destroy}
    )

    assert {:ok, c0} = RecyclingPool.checkout(:rp_reuse, 2_000)
    assert :ok = RecyclingPool.checkin(:rp_reuse, c0)
    assert {:ok, ^c0} = RecyclingPool.checkout(:rp_reuse, 2_000)
    assert destroyed.() == []
  end