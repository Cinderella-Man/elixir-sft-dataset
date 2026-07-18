  test "an eagerly created connection starts at zero uses" do
    {destroy, destroyed} = destroy_tracker()

    start_supervised!(
      {RecyclingPool,
       name: :rp_eager_uses, min_size: 1, max_size: 1, max_uses: 2, destroy: destroy}
    )

    assert {:ok, c} = RecyclingPool.checkout(:rp_eager_uses, 2_000)
    assert :ok = RecyclingPool.checkin(:rp_eager_uses, c)
    # Only one use so far: not retired, and reused.
    assert destroyed.() == []
    assert {:ok, ^c} = RecyclingPool.checkout(:rp_eager_uses, 2_000)
    assert :ok = RecyclingPool.checkin(:rp_eager_uses, c)
    # Second use reaches max_uses: retired now.
    assert destroyed.() == [c]
  end