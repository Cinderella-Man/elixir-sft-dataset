  test "raised exceptions count as failures and don't crash the GenServer", %{cb: cb} do
    raise_fn = fn -> raise "boom" end

    assert {:error, %RuntimeError{message: "boom"}} =
             LeakyBucketCircuitBreaker.call(cb, raise_fn)

    pid = Process.whereis(cb)
    assert Process.alive?(pid)

    # 4 more raises fill the bucket and trip
    for _ <- 1..4, do: LeakyBucketCircuitBreaker.call(cb, raise_fn)
    assert :open = LeakyBucketCircuitBreaker.state(cb)
  end