  test "random is called with the clamped delay when it is exactly 1", %{rw: _rw} do
    rw2 = recording_server()
    func = fail_then_succeed(1, :done)

    assert {:ok, :done} = RetryWorker.execute(rw2, func, max_retries: 1, base_delay_ms: 1)
    assert DelayRecorder.delays() == [1]
  end