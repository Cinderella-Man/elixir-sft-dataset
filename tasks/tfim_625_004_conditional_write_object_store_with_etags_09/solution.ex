  test "if_match on a missing key fails the precondition", %{os: os} do
    ConditionalObjectStorage.create_bucket(os, "b")

    assert {:error, :precondition_failed} =
             ConditionalObjectStorage.put_object(os, "b", "k", "v", if_match: "anything")

    assert {:error, :not_found} = ConditionalObjectStorage.get_object(os, "b", "k")
  end