  test "submit and await multiple tasks", %{pool: pool} do
    {:ok, r1} = RetryPool.submit(pool, quick_task(:a))
    {:ok, r2} = RetryPool.submit(pool, quick_task(:b))
    {:ok, r3} = RetryPool.submit(pool, quick_task(:c))

    assert {:ok, :a} = RetryPool.await(pool, r1, 1_000)
    assert {:ok, :b} = RetryPool.await(pool, r2, 1_000)
    assert {:ok, :c} = RetryPool.await(pool, r3, 1_000)
  end