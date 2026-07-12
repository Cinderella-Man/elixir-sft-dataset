  test "label matchers select series that contain all specified labels", %{db: db} do
    :ok = RollupTSDB.insert(db, "http", %{"method" => "GET", "status" => "200"}, 100, 1)
    :ok = RollupTSDB.insert(db, "http", %{"method" => "POST", "status" => "200"}, 100, 2)
    :ok = RollupTSDB.insert(db, "http", %{"method" => "GET", "status" => "500"}, 100, 3)

    result = RollupTSDB.query(db, "http", %{"status" => "200"}, {0, 900})
    assert length(result) == 2
  end