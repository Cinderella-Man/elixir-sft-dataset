  test "a key's burst-start time does not leak into another key's max-wait window" do
    MaxWaitDebouncer.call("a", 150, 200, notify({:k, :a}))
    refute_receive {:k, :a}, 120

    # "b" opens its own burst at ~t=120, so its max deadline is ~t=420. If it
    # shared "a"'s burst start (~t=0) the remaining window would be ~180ms and
    # "b" would fire at ~t=300, inside the refute window below.
    MaxWaitDebouncer.call("b", 300, 300, notify({:k, :b}))

    assert_receive {:k, :a}, 200
    refute_receive {:k, :b}, 200
    assert_receive {:k, :b}, 250
  end