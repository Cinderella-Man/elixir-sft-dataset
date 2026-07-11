  test "get with if_none_match matching returns not_modified", %{os: os} do
    ConditionalObjectStorage.create_bucket(os, "b")
    {:ok, etag} = ConditionalObjectStorage.put_object(os, "b", "k", "body")

    assert {:error, :not_modified} =
             ConditionalObjectStorage.get_object(os, "b", "k", if_none_match: etag)

    assert {:ok, %{data: "body"}} =
             ConditionalObjectStorage.get_object(os, "b", "k", if_none_match: "other")
  end