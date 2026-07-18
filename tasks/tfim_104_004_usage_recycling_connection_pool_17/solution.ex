  test "a lazily created connection starts at zero uses" do
    {destroy, destroyed} = destroy_tracker()

    start_supervised!(
      {RecyclingPool, name: :rp_lazy_uses, max_size: 1, max_uses: 2, destroy: destroy}
    )

    assert {:ok, c} = RecyclingPool.checkout(:rp_lazy_uses, 2_000)
    assert :ok = RecyclingPool.checkin(:rp_lazy_uses, c)
    assert destroyed.() == []
    assert {:ok, ^c} = RecyclingPool.checkout(:rp_lazy_uses, 2_000)
    assert :ok = RecyclingPool.checkin(:rp_lazy_uses, c)
    assert destroyed.() == [c]
  end