  test "trips when bucket reaches capacity (burst)", %{cb: cb} do
    # 5 failures in quick succession fills the bucket to capacity
    for _ <- 1..5, do: LeakyBucketCircuitBreaker.call(cb, err_fn())
    assert :open = LeakyBucketCircuitBreaker.state(cb)
  end