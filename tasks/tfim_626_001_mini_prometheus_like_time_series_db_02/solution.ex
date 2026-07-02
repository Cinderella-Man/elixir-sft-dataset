  test "insert and retrieve a single data point", %{db: db} do
    assert :ok = TSDB.insert(db, "cpu", %{"host" => "a"}, 100, 0.5)

    result = TSDB.query(db, "cpu", %{"host" => "a"}, {0, 200})
    assert [{%{"host" => "a"}, [{100, 0.5}]}] = result
  end