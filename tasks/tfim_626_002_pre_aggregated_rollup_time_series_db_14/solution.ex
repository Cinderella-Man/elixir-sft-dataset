  test "cleanup removes a series left with no buckets", %{db: db} do
    :ok = RollupTSDB.insert(db, "m", %{"host" => "a"}, 100, 1)

    Clock.set(100_000)
    :ok = sync_cleanup(db)

    assert [] = RollupTSDB.query(db, "m", %{"host" => "a"}, {0, 200_000})
  end