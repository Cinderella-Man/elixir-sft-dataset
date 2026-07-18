  test "probe failure → :open with restarted reset timeout", %{cb: cb} do
    for _ <- 1..5, do: LeakyBucketCircuitBreaker.call(cb, err_fn())
    Clock.advance(1_000)

    assert {:error, :f} = LeakyBucketCircuitBreaker.call(cb, err_fn())
    assert :open = LeakyBucketCircuitBreaker.state(cb)

    Clock.advance(500)
    assert :open = LeakyBucketCircuitBreaker.state(cb)
    Clock.advance(500)
    assert :half_open = LeakyBucketCircuitBreaker.state(cb)
  end