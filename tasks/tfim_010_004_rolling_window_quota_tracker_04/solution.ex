  test "record rejects when quota would be exceeded", %{tracker: t} do
    {:ok, _} = QuotaTracker.record(t, :api, 8, 10, 1_000)

    assert {:error, :quota_exceeded, 1} = QuotaTracker.record(t, :api, 3, 10, 1_000)
  end