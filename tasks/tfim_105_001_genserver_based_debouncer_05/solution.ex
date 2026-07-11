  test "each call resets the timer" do
    # t=0: schedule v1 (would fire at t=200 if never reset)
    Debouncer.call("k", 200, notify(:v1))

    Process.sleep(100)

    # t=100: reset the timer with v2 (should now fire near t=300)
    Debouncer.call("k", 200, notify(:v2))

    # From t=100..t=250: v1 would have fired at t=200 if the timer
    # had NOT been reset. It must not.
    refute_receive :v1, 150

    # v2 fires after its own full delay.
    assert_receive :v2, 500

    # v1 never runs.
    refute_received :v1
  end