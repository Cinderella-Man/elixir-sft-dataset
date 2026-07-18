  test "Store.save stamps an ISO 8601 UTC timestamp and echoes the caller metadata", _ctx do
    metadata = %{original_name: "stamped.json", size: 2, content_type: "application/json"}

    assert {:ok, record} = FileUpload.Store.save(:test_store, metadata)

    assert is_binary(record.uploaded_at)
    assert String.ends_with?(record.uploaded_at, "Z")
    assert {:ok, _dt, 0} = DateTime.from_iso8601(record.uploaded_at)

    assert record.original_name == "stamped.json"
    assert record.size == 2
    assert record.content_type == "application/json"
    assert is_binary(record.id)
  end