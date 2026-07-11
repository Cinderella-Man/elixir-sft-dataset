  test "put and get an object", %{os: os} do
    ObjectStorage.create_bucket(os, "data")

    assert :ok =
             ObjectStorage.put_object(os, "data", "greeting.txt", "hello world", "text/plain", %{
               "author" => "test"
             })

    assert {:ok, obj} = ObjectStorage.get_object(os, "data", "greeting.txt")
    assert obj.data == "hello world"
    assert obj.content_type == "text/plain"
    assert obj.metadata == %{"author" => "test"}
    assert obj.size == byte_size("hello world")
    assert %DateTime{} = obj.last_modified
  end