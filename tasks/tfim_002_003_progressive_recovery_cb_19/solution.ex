  test "default stage 0 tolerates zero failures" do
    cb = default_cb_in_recovering()

    assert {:error, :f} = ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end