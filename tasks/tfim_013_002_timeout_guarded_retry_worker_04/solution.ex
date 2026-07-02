  test "retries and succeeds on the Nth attempt", %{rw: rw} do
    func = fail_then_succeed(3, :recovered)

    assert {:ok, :recovered} =
             TimeoutRetryWorker.execute(rw, func,
               max_retries: 5,
               base_delay_ms: 100,
               attempt_timeout_ms: 5_000
             )

    # 3 failures + 1 success = 4 total calls
    assert Counter.get() == 4
  end