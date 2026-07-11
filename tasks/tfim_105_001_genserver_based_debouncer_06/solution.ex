  test "a stale timer message cannot run the replacement func early" do
    # Arm f1, then SUSPEND the server so we control the message order: the
    # re-debounce cast is queued first, and the old timer's fire message lands
    # behind it while the server is suspended. On resume the server processes
    # the re-debounce, then the old timer's message — which must be recognized
    # as stale and dropped, not run the freshly armed func ~150ms early.
    Debouncer.call("k", 80, notify(:old_func))
    pid = Process.whereis(Debouncer)
    :sys.suspend(pid)
    Debouncer.call("k", 300, notify(:new_func))
    Process.sleep(150)
    :sys.resume(pid)

    # The replacement waits out its own full delay...
    refute_receive :new_func, 200
    # ...then fires exactly once.
    assert_receive :new_func, 500
    # The func it replaced never runs.
    refute_received :old_func
  end