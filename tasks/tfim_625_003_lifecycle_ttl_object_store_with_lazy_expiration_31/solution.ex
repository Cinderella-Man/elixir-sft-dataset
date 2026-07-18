  test "list_objects sorts several live keys lexicographically", %{os: os} do
    TtlObjectStorage.create_bucket(os, "b")
    :ok = TtlObjectStorage.put_object(os, "b", "delta", "4")
    :ok = TtlObjectStorage.put_object(os, "b", "alpha", "1")
    :ok = TtlObjectStorage.put_object(os, "b", "Charlie", "3")
    :ok = TtlObjectStorage.put_object(os, "b", "bravo", "2")

    assert {:ok, listing} = TtlObjectStorage.list_objects(os, "b")
    assert Enum.map(listing, & &1.key) == ["Charlie", "alpha", "bravo", "delta"]
    assert Enum.map(listing, & &1.size) == [1, 1, 1, 1]
  end