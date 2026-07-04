  test "partial-second leak works correctly", %{cb: cb} do
    for _ <- 1..3, do: LeakyBucketCircuitBreaker.call(cb, err_fn())
    # 500ms at 1.0 drops/sec = 0.5 leaked
    Clock.advance(500)
    assert 2.5 = LeakyBucketCircuitBreaker.bucket_level(cb)
  end