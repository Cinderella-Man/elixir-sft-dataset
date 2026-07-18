  test "registering again after unregister arms a fresh timer" do
    test = self()
    :ok = Watchdog.register(:worker, dummy_pid(), 10_000, notifier(test, :first))
    assert :ok = Watchdog.unregister(:worker)

    :ok = Watchdog.register(:worker, dummy_pid(), 60, notifier(test, :second))

    assert_receive {:second, :worker}, 1_000
    refute_receive {:first, :worker}, 50
  end