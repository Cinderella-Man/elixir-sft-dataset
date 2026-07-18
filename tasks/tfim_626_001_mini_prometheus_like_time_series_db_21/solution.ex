  test "insert and query with empty labels", %{db: db} do
    :ok = TSDB.insert(db, "m", %{}, 100, 42)

    [{labels, [{100, 42}]}] = TSDB.query(db, "m", %{}, {0, 200})
    assert labels == %{}
  end