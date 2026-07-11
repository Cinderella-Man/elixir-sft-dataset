  test "put and get with default (infinite) ttl", %{os: os} do
    TtlObjectStorage.create_bucket(os, "b")
    assert :ok = TtlObjectStorage.put_object(os, "b", "k", "hello")

    assert {:ok, obj} = TtlObjectStorage.get_object(os, "b", "k")
    assert obj.data == "hello"
    assert obj.size == byte_size("hello")
    assert %DateTime{} = obj.last_modified
  end