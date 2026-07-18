  test "delete with a stale etag from a previous version leaves the object in place", %{os: os} do
    ConditionalObjectStorage.create_bucket(os, "b")
    {:ok, old_etag} = ConditionalObjectStorage.put_object(os, "b", "k", "v1")
    {:ok, new_etag} = ConditionalObjectStorage.put_object(os, "b", "k", "v2")

    assert {:error, :precondition_failed} =
             ConditionalObjectStorage.delete_object(os, "b", "k", if_match: old_etag)

    assert {:ok, %{data: "v2"}} = ConditionalObjectStorage.get_object(os, "b", "k")
    assert :ok = ConditionalObjectStorage.delete_object(os, "b", "k", if_match: new_etag)
    assert {:error, :not_found} = ConditionalObjectStorage.get_object(os, "b", "k")
  end