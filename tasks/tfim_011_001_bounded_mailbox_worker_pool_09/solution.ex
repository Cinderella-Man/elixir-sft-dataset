  test "status reflects pool state accurately", %{pool: pool} do
    # Initially all idle
    status = WorkerPool.status(pool)
    assert status.idle_workers == 2
    assert status.busy_workers == 0
    assert status.queue_length == 0
  end