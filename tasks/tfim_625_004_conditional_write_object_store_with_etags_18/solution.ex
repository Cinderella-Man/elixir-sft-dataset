  test "put with a precondition on a missing bucket reports bucket_not_found not precondition", %{
    os: os
  } do
    assert {:error, :bucket_not_found} =
             ConditionalObjectStorage.put_object(os, "nope", "k", "v", if_none_match: "*")

    assert {:error, :bucket_not_found} =
             ConditionalObjectStorage.put_object(os, "nope", "k", "v", if_match: "anything")
  end