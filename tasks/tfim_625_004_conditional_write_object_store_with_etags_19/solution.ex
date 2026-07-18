  test "delete with if_match on a missing bucket reports bucket_not_found", %{os: os} do
    assert {:error, :bucket_not_found} =
             ConditionalObjectStorage.delete_object(os, "nope", "k", if_match: "some-etag")
  end