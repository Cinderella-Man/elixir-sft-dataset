  test "succeeds on the very last retry", %{rw: rw} do
    func = fail_then_succeed(3, :last_chance)

    assert {:ok, :last_chance} =
             RetryWorker.execute(rw, func, max_retries: 3, base_delay_ms: 100)

    # 3 failures + 1 success = 4 total calls = initial + 3 retries
    assert Counter.get() == 4
  end