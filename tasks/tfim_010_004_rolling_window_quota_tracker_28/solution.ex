  test "reset removes the key from the keys listing", %{tracker: t} do
    {:ok, _} = QuotaTracker.record(t, :api, 5, 10, 1_000)
    {:ok, _} = QuotaTracker.record(t, :uploads, 3, 10, 1_000)

    :ok = QuotaTracker.reset(t, :api)

    assert QuotaTracker.keys(t) == [:uploads]
  end