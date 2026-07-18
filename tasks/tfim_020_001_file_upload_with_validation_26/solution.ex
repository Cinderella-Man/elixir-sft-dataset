  test "Store.save generates an id in canonical UUID v4 form", _ctx do
    metadata = %{original_name: "uuid_shape.csv", size: 9, content_type: "text/csv"}

    assert {:ok, record} = FileUpload.Store.save(:test_store, metadata)

    uuid_v4 = ~r/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/

    assert record.id =~ uuid_v4
    assert {:ok, fetched} = FileUpload.Store.get(:test_store, record.id)
    assert fetched.id == record.id
  end