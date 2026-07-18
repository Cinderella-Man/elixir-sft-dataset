  test "start_link/1 registers under a custom :name and returns {:ok, pid}" do
    assert {:ok, pid} = EdgeDebouncer.start_link(name: :edge_debouncer_alt)

    assert Process.whereis(:edge_debouncer_alt) == pid
    # The default-named process from setup/1 is a distinct registration.
    assert Process.whereis(EdgeDebouncer) != pid
  end