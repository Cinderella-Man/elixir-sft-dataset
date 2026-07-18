  test "each successful submit returns a distinct ref", %{pool: pool} do
    {:ok, r1} = PriorityWorkerPool.submit(pool, quick_task(:a), :normal)
    {:ok, r2} = PriorityWorkerPool.submit(pool, quick_task(:b), :normal)

    assert is_reference(r1)
    assert is_reference(r2)
    assert r1 != r2
  end