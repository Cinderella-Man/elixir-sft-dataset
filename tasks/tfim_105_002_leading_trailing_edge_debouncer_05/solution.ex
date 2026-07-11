  test "both edges fire leading immediately and trailing at the end" do
    EdgeDebouncer.call("k", 150, notify({:ran, 1}), edge: :both)
    EdgeDebouncer.call("k", 150, notify({:ran, 2}), edge: :both)
    EdgeDebouncer.call("k", 150, notify({:ran, 3}), edge: :both)

    # Leading is the first func.
    assert_receive {:ran, 1}, 100
    # Trailing is the most recent func.
    assert_receive {:ran, 3}, 600
    # The middle func never runs.
    refute_received {:ran, 2}
  end