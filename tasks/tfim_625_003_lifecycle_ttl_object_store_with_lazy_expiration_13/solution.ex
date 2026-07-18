  test "list_objects excludes expired objects and is sorted", %{os: os} do
    TtlObjectStorage.create_bucket(os, "b")
    :ok = TtlObjectStorage.put_object(os, "b", "keep", "1", ttl_ms: 5_000)
    :ok = TtlObjectStorage.put_object(os, "b", "gone", "22", ttl_ms: 40)
    Process.sleep(120)

    assert {:ok, [obj]} = TtlObjectStorage.list_objects(os, "b")
    assert obj.key == "keep"
    assert obj.size == 1
    assert %DateTime{} = obj.last_modified
  end