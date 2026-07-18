  test "retention defaults to one hour when the option is omitted" do
    {:ok, db} =
      RollupTSDB.start_link(
        clock: &Clock.now/0,
        bucket_duration_ms: 1_000,
        cleanup_interval_ms: :infinity
      )

    # bucket 0 expires at now == 3_601_000; bucket 5000 not until 3_606_000
    :ok = RollupTSDB.insert(db, "m", %{}, 100, 1)
    :ok = RollupTSDB.insert(db, "m", %{}, 5_500, 2)

    Clock.set(3_600_999)
    :ok = sync_cleanup(db)
    [{_labels, before}] = RollupTSDB.query(db, "m", %{}, {0, 10_000})
    assert Enum.map(before, &elem(&1, 0)) == [0, 5_000]

    Clock.set(3_601_000)
    :ok = sync_cleanup(db)
    [{_labels, kept}] = RollupTSDB.query(db, "m", %{}, {0, 10_000})
    assert Enum.map(kept, &elem(&1, 0)) == [5_000]
  end