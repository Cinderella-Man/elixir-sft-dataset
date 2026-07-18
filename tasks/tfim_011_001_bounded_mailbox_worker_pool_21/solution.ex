  test "pool is addressable by its registered name", _context do
    name = :"named_#{:erlang.unique_integer([:positive])}"
    start_supervised!({WorkerPool, pool_size: 1, name: name}, id: :named_pool)

    {:ok, ref} = WorkerPool.submit(name, quick_task(:via_name))
    assert {:ok, :via_name} = WorkerPool.await(name, ref, 1_000)
    assert %{idle_workers: _, busy_workers: _} = WorkerPool.status(name)
  end