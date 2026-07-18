  test "the recorded backoff sequence doubles from base_delay_ms", %{rw: _rw} do
    rw2 = recording_server()
    func = fail_then_succeed(3, :done)

    assert {:ok, :done} = RetryWorker.execute(rw2, func, max_retries: 3, base_delay_ms: 4)
    assert DelayRecorder.delays() == [4, 8, 16]
  end