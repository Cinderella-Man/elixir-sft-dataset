  test "recorded delays reflect clamping to max_delay_ms", %{rw: _rw} do
    rw2 = recording_server()
    func = fail_then_succeed(4, :done)

    assert {:ok, :done} =
             RetryWorker.execute(rw2, func, max_retries: 4, base_delay_ms: 4, max_delay_ms: 10)

    assert DelayRecorder.delays() == [4, 8, 10, 10]
  end