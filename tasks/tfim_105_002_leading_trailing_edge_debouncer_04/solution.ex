  test "leading edge runs the first func immediately and nothing else" do
    EdgeDebouncer.call("k", 200, notify({:ran, 1}), edge: :leading)
    EdgeDebouncer.call("k", 200, notify({:ran, 2}), edge: :leading)
    EdgeDebouncer.call("k", 200, notify({:ran, 3}), edge: :leading)

    # First func fires right away.
    assert_receive {:ran, 1}, 100
    # No later func ever runs, and no trailing execution occurs.
    refute_receive {:ran, 2}, 400
    refute_received {:ran, 3}
  end