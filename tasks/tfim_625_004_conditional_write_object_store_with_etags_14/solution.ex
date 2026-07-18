  test "delete with if_match succeeds only on a matching etag", %{os: os} do
    ConditionalObjectStorage.create_bucket(os, "b")
    {:ok, etag} = ConditionalObjectStorage.put_object(os, "b", "k", "v")

    assert {:error, :precondition_failed} =
             ConditionalObjectStorage.delete_object(os, "b", "k", if_match: "wrong")

    # object still there
    assert {:ok, %{data: "v"}} = ConditionalObjectStorage.get_object(os, "b", "k")

    assert :ok = ConditionalObjectStorage.delete_object(os, "b", "k", if_match: etag)
    assert {:error, :not_found} = ConditionalObjectStorage.get_object(os, "b", "k")
  end