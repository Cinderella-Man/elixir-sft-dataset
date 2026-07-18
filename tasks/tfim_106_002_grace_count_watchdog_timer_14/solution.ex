  test "heartbeat for an unknown name is a harmless no-op" do
    assert :ok = GraceWatchdog.heartbeat(:nope)
  end