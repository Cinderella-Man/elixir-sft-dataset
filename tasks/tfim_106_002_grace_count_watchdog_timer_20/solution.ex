  test "re-registering with a longer interval does not fire at the old deadline" do
    test = self()
    :ok = GraceWatchdog.register(:w, dummy_pid(), 40, 1, notifier(test, :old))
    :ok = GraceWatchdog.register(:w, dummy_pid(), 10_000, 1, notifier(test, :new))

    refute_receive {:old, :w, _}, 300
    refute_receive {:new, :w, _}, 10
    assert {:ok, 0} = GraceWatchdog.misses(:w)
  end