  test "if_match fails on a stale etag and leaves the object unchanged", %{os: os} do
    ConditionalObjectStorage.create_bucket(os, "b")
    {:ok, _e1} = ConditionalObjectStorage.put_object(os, "b", "k", "v1")

    assert {:error, :precondition_failed} =
             ConditionalObjectStorage.put_object(os, "b", "k", "v2", if_match: "stale-etag")

    assert {:ok, %{data: "v1"}} = ConditionalObjectStorage.get_object(os, "b", "k")
  end