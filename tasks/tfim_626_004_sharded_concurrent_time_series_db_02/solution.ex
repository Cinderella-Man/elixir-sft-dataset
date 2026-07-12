  test "insert returns :ok and query retrieves the point", %{db: db} do
    assert :ok = ShardedTSDB.insert(db, "cpu", %{"host" => "a"}, 100, 0.5)

    result = ShardedTSDB.query(db, "cpu", %{"host" => "a"}, {0, 200})
    assert [{%{"host" => "a"}, [{100, 0.5}]}] = result
  end