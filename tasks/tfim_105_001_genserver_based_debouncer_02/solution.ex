  test "coalesces rapid calls on the same key — only the last func runs" do
    Debouncer.call("k", 150, notify({:ran, 1}))
    Debouncer.call("k", 150, notify({:ran, 2}))
    Debouncer.call("k", 150, notify({:ran, 3}))

    # Only the most recently supplied func should ever fire.
    assert_receive {:ran, 3}, 600

    # The earlier funcs from the burst must never have run.
    refute_received {:ran, 1}
    refute_received {:ran, 2}

    # And nothing else fires afterwards.
    refute_receive {:ran, _}, 250
  end