  test "remaining reports negative headroom when usage exceeds the quota",
       %{tracker: t} do
    {:ok, _} = QuotaTracker.record(t, :api, 8, 10, 1_000)

    # 8 units are counted in the window; against a quota of 5 the promised
    # value is 5 - 8 = -3 (the formula is stated with no clamping).
    assert {:ok, -3} = QuotaTracker.remaining(t, :api, 5, 1_000)
  end