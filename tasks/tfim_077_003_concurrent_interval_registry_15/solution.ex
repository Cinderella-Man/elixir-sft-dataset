  test "stop shuts down an independently started server", %{server: _s} do
    {:ok, other} = IntervalRegistry.start_link()
    {:ok, _} = IntervalRegistry.insert(other, {1, 2})
    assert IntervalRegistry.size(other) == 1

    assert Process.alive?(other)
    assert :ok = IntervalRegistry.stop(other)
    refute Process.alive?(other)

    # A stopped server no longer answers calls.
    assert catch_exit(IntervalRegistry.size(other))
  end