  test "random is never called when max_delay_ms is zero", %{rw: _rw} do
    rw2 = recording_server()
    func = fail_then_succeed(2, :done)

    assert {:ok, :done} =
             RetryWorker.execute(rw2, func, max_retries: 2, base_delay_ms: 100, max_delay_ms: 0)

    assert DelayRecorder.delays() == []
  end