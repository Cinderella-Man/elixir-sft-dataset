  test "call/3 returns promptly even while the server is not processing messages" do
    pid = Process.whereis(Debouncer)

    # With the server unable to process anything, a blocking request would hang.
    :sys.suspend(pid)
    {micros, result} = :timer.tc(fn -> Debouncer.call("busy", 20, notify(:busy_ran)) end)
    :sys.resume(pid)

    assert result == :ok
    assert micros < 100_000

    # The fire-and-forget request is still honored once the server runs again.
    assert_receive :busy_ran, 400
  end