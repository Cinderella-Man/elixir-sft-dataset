  test "a replacement call with a shorter delay fires on the new shorter delay" do
    Debouncer.call(:shrink, 500, notify(:slow_v1))
    Debouncer.call(:shrink, 20, notify(:fast_v2))

    # The delay in force is the newest call's 20ms, not the earlier 500ms.
    assert_receive :fast_v2, 250
    refute_received :slow_v1

    # And the replaced func never runs, not even at the old 500ms deadline.
    refute_receive :slow_v1, 700
  end