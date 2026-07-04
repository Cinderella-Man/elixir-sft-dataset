  test "returns error when all retries are exhausted", %{rw: rw} do
    func = fail_then_succeed(10, :never)

    assert {:error, :max_retries_exceeded, :boom} =
             RetryWorker.execute(rw, func, max_retries: 3, base_delay_ms: 100)

    # initial attempt + 3 retries = 4 calls total
    assert Counter.get() == 4
  end