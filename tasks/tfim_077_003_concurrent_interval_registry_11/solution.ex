  test "stop terminates the running server", %{server: s} do
    assert Process.alive?(s)
    ref = Process.monitor(s)

    assert :ok = IntervalRegistry.stop(s)

    assert_receive {:DOWN, ^ref, :process, ^s, _reason}, 1_000
    refute Process.alive?(s)
  end