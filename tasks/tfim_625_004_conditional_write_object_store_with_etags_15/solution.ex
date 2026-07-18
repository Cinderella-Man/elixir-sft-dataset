  test "delete with if_match on a missing key fails the precondition", %{os: os} do
    ConditionalObjectStorage.create_bucket(os, "b")

    assert {:error, :precondition_failed} =
             ConditionalObjectStorage.delete_object(os, "b", "missing", if_match: "x")
  end