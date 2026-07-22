  test "one caller's slow in-flight attempt never blocks another caller", %{rw: rw} do
    test_pid = self()

    # Parks inside its attempt Task until released — a long-running attempt
    # nowhere near its generous 60s timeout.
    slow = fn ->
      send(test_pid, {:slow_started, self()})

      receive do
        :release -> {:ok, :released}
      end
    end

    slow_task =
      Task.async(fn ->
        TimeoutRetryWorker.execute(rw, slow, attempt_timeout_ms: 60_000)
      end)

    assert_receive {:slow_started, slow_pid}, 1_000

    # With that attempt in flight, a second caller must complete promptly:
    # the server may not sit in a blocking yield on the first attempt.
    fast_task =
      Task.async(fn ->
        TimeoutRetryWorker.execute(rw, fn -> {:ok, :fast} end)
      end)

    assert {:ok, :fast} = Task.await(fast_task, 1_000)

    send(slow_pid, :release)
    assert {:ok, :released} = Task.await(slow_task, 1_000)
  end