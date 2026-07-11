  test "if_none_match * creates only when absent", %{os: os} do
    ConditionalObjectStorage.create_bucket(os, "b")

    assert {:ok, _} =
             ConditionalObjectStorage.put_object(os, "b", "k", "first", if_none_match: "*")

    assert {:error, :precondition_failed} =
             ConditionalObjectStorage.put_object(os, "b", "k", "second", if_none_match: "*")

    # unchanged
    assert {:ok, %{data: "first"}} = ConditionalObjectStorage.get_object(os, "b", "k")
  end