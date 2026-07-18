  test "the injected random receives the default clamped delay of 100", %{rw: _rw} do
    rw2 = recording_server()
    func = fail_then_succeed(1, :done)

    assert {:ok, :done} = RetryWorker.execute(rw2, func, max_retries: 1)
    assert DelayRecorder.delays() == [100]
  end