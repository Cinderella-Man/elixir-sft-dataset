  test "re-registering resets the accumulated miss count to zero" do
    test = self()
    :ok = GraceWatchdog.register(:w, dummy_pid(), 25, 10, notifier(test))
    :ok = GraceWatchdog.register(:gate, dummy_pid(), 70, 1, notifier(test, :gate))

    assert_receive {:gate, :gate, 1}, 1_000
    assert {:ok, accumulated} = GraceWatchdog.misses(:w)
    assert accumulated >= 1

    :ok = GraceWatchdog.register(:w, dummy_pid(), 10_000, 5, notifier(test))
    assert {:ok, 0} = GraceWatchdog.misses(:w)
  end