  test "a second call restarts the delay so trailing survives the original deadline" do
    # t0: arm a 200ms trailing burst for "k".
    EdgeDebouncer.call("k", 200, notify(:late))

    # A separate key acts as a deterministic ~120ms clock (keys are independent).
    EdgeDebouncer.call("clock", 120, notify(:tick))
    assert_receive :tick, 500

    # ~t0+120: re-call "k" — the deadline must restart from now (~t0+320),
    # not stay at the original ~t0+200.
    EdgeDebouncer.call("k", 200, notify(:late))
    refute_receive :late, 120

    assert_receive :late, 500
  end