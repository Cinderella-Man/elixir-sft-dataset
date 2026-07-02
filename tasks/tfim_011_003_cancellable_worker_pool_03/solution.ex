  test "submit and await multiple tasks", %{pool: pool} do
    {:ok, r1} = CancellablePool.submit(pool, quick_task(:a))
    {:ok, r2} = CancellablePool.submit(pool, quick_task(:b))
    {:ok, r3} = CancellablePool.submit(pool, quick_task(:c))

    assert {:ok, :a} = CancellablePool.await(pool, r1, 1_000)
    assert {:ok, :b} = CancellablePool.await(pool, r2, 1_000)
    assert {:ok, :c} = CancellablePool.await(pool, r3, 1_000)
  end