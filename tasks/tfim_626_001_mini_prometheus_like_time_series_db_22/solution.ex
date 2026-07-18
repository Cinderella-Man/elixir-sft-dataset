  test "query_agg with no matching data returns empty list", %{db: db} do
    assert [] = TSDB.query_agg(db, "nonexistent", %{}, {0, 1000}, :sum, 500)
  end