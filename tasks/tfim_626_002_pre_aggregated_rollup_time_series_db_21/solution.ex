  test "bucket width defaults to one minute when the option is omitted" do
    {:ok, db} = RollupTSDB.start_link(clock: &Clock.now/0, cleanup_interval_ms: :infinity)

    :ok = RollupTSDB.insert(db, "m", %{}, 0, 1)
    :ok = RollupTSDB.insert(db, "m", %{}, 59_999, 2)
    :ok = RollupTSDB.insert(db, "m", %{}, 60_000, 3)

    [{_labels, buckets}] = RollupTSDB.query(db, "m", %{}, {0, 120_000})
    assert Enum.map(buckets, &elem(&1, 0)) == [0, 60_000]

    [{0, b0}, {60_000, b1}] = buckets
    assert b0.count == 2
    assert b1.count == 1
  end