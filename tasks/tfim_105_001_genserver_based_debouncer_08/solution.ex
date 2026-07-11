  test "coalescing one key leaves other keys untouched" do
    # Burst on "a" — only the last should survive.
    Debouncer.call("a", 150, notify({:a, 1}))
    Debouncer.call("a", 150, notify({:a, 2}))

    # A single, independent call on "b".
    Debouncer.call("b", 150, notify(:b_ran))

    assert_receive {:a, 2}, 500
    assert_receive :b_ran, 500

    refute_received {:a, 1}
  end