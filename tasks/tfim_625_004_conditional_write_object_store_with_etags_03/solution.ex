  test "put returns the sha256 hex etag of the data", %{os: os} do
    ConditionalObjectStorage.create_bucket(os, "b")
    assert {:ok, etag} = ConditionalObjectStorage.put_object(os, "b", "k", "hello world")
    assert etag == etag_of("hello world")
  end