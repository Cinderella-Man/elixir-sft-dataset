  test "re-registering with a longer interval outlives the replaced deadline" do
    test = self()

    # First registration would fire at 60ms; the replacement extends the window to 400ms.
    :ok = Watchdog.register(:worker, dummy_pid(), 60, notifier(test, :old))
    :ok = Watchdog.register(:worker, dummy_pid(), 400, notifier(test, :new))

    # Drive real time well past the OLD 60ms deadline: nothing may fire from it.
    refute_receive {:old, :worker}, 200
    refute_receive {:new, :worker}, 0

    # The replacement's own (extended) deadline must still be honoured.
    assert_receive {:new, :worker}, 1_000
    refute_receive {:old, :worker}, 50
  end