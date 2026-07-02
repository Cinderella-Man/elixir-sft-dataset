  test "retries and succeeds on the Nth attempt", %{rw: rw} do
    func = fail_then_succeed(3, :recovered)

    assert {:ok, :recovered} =
             RetryWorker.execute(rw, func, max_retries: 5, base_delay_ms: 100)

    # Should have been called 4 times: 3 failures + 1 success
    assert Counter.get() == 4
  end