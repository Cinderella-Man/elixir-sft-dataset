  test "keys returns all tracked keys", %{tracker: t} do
    {:ok, _} = QuotaTracker.record(t, :api, 1, 10, 1_000)
    {:ok, _} = QuotaTracker.record(t, :uploads, 1, 10, 1_000)
    {:ok, _} = QuotaTracker.record(t, :downloads, 1, 10, 1_000)

    keys = QuotaTracker.keys(t)
    assert Enum.sort(keys) == [:api, :downloads, :uploads]
  end