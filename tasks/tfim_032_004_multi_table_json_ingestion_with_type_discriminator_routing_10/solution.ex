  test "handles an empty JSON array gracefully" do
    path = tmp_path("empty_multi.json")
    write_json!(path, [])

    assert {:ok, stats} =
             MultiSchemaIngestion.ingest(TestRepo, routing(), path)

    assert stats.total == 0
    assert stats.unroutable == 0
    assert stats.missing_type == 0
    # Both schemas should appear in by_schema with zero counts
    assert stats.by_schema[Order] == %{inserted: 0, failed: 0}
    assert stats.by_schema[Refund] == %{inserted: 0, failed: 0}
  end