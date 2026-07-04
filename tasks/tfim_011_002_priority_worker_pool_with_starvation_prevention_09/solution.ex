  test "status reflects pool state accurately", %{pool: pool} do
    status = PriorityWorkerPool.status(pool)
    assert status.idle_workers == 2
    assert status.busy_workers == 0
    assert status.queue_high == 0
    assert status.queue_normal == 0
    assert status.queue_low == 0
    assert status.total_queue_length == 0
  end