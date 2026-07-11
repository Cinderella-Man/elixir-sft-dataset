  test "heartbeat for an unknown name is a harmless no-op" do
    assert :ok = Watchdog.heartbeat(:never_registered)
  end