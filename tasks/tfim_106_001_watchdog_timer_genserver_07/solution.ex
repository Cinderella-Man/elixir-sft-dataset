  test "unregistering an unknown name is a harmless no-op" do
    assert :ok = Watchdog.unregister(:never_registered)
  end