  test "series_count is zero before any insert", %{db: db} do
    assert ShardedTSDB.series_count(db) == 0
  end