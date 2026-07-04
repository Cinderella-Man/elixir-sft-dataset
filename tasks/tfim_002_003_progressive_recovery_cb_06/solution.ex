  test "successful probe enters :recovering, not :closed directly", %{cb: cb} do
    trip_to_half_open(cb)

    assert {:ok, :v} = ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)
  end