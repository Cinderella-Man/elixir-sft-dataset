  test "the most recently supplied handler receives the full batch" do
    BatchDebouncer.call("k", 150, 1, report(:h1))
    BatchDebouncer.call("k", 150, 2, report(:h2))
    BatchDebouncer.call("k", 150, 3, report(:h3))

    # h3 is the latest handler; it gets the whole ordered batch.
    assert_receive {:h3, [1, 2, 3]}, 600
    refute_received {:h1, _}
    refute_received {:h2, _}
  end