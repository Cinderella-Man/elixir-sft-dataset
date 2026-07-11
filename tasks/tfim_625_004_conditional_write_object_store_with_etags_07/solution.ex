  test "if_match succeeds on a matching etag and returns the new etag", %{os: os} do
    ConditionalObjectStorage.create_bucket(os, "b")
    {:ok, e1} = ConditionalObjectStorage.put_object(os, "b", "k", "v1")

    assert {:ok, e2} = ConditionalObjectStorage.put_object(os, "b", "k", "v2", if_match: e1)
    assert e2 == etag_of("v2")
    assert {:ok, %{data: "v2"}} = ConditionalObjectStorage.get_object(os, "b", "k")
  end