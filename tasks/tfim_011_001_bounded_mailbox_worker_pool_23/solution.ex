  test "each submit returns a distinct reference", %{pool: pool} do
    {:ok, r1} = WorkerPool.submit(pool, quick_task(:x))
    {:ok, r2} = WorkerPool.submit(pool, quick_task(:y))
    assert r1 != r2
    assert is_reference(r1)
    assert is_reference(r2)
  end