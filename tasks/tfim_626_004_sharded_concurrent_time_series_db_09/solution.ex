  test "label matchers select series containing all specified labels", %{db: db} do
    :ok = ShardedTSDB.insert(db, "http", %{"method" => "GET", "status" => "200"}, 100, 1)
    :ok = ShardedTSDB.insert(db, "http", %{"method" => "POST", "status" => "200"}, 100, 2)
    :ok = ShardedTSDB.insert(db, "http", %{"method" => "GET", "status" => "500"}, 100, 3)

    result = ShardedTSDB.query(db, "http", %{"status" => "200"}, {0, 200})
    assert length(result) == 2
  end