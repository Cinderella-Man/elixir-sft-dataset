  test "same labels under different metrics are distinct series", %{db: db} do
    :ok = ShardedTSDB.insert(db, "cpu", %{"host" => "a"}, 100, 1)
    :ok = ShardedTSDB.insert(db, "mem", %{"host" => "a"}, 100, 2)

    assert ShardedTSDB.series_count(db) == 2
    assert [{_, [{100, 1}]}] = ShardedTSDB.query(db, "cpu", %{"host" => "a"}, {0, 200})
    assert [{_, [{100, 2}]}] = ShardedTSDB.query(db, "mem", %{"host" => "a"}, {0, 200})
  end