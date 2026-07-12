  test "label matchers requiring an unmatched value return nothing", %{db: db} do
    :ok = ShardedTSDB.insert(db, "http", %{"method" => "GET"}, 100, 1)
    :ok = ShardedTSDB.insert(db, "http", %{"method" => "PUT"}, 100, 2)

    assert [] = ShardedTSDB.query(db, "http", %{"method" => "DELETE"}, {0, 200})
  end