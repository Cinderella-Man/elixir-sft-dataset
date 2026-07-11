  test "get returns data, etag, size and last_modified", %{os: os} do
    ConditionalObjectStorage.create_bucket(os, "b")
    ConditionalObjectStorage.put_object(os, "b", "k", "payload")

    assert {:ok, obj} = ConditionalObjectStorage.get_object(os, "b", "k")
    assert obj.data == "payload"
    assert obj.etag == etag_of("payload")
    assert obj.size == byte_size("payload")
    assert %DateTime{} = obj.last_modified
  end