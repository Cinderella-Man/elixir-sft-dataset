  test "delete an object", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    ObjectStorage.put_object(os, "b", "k", "v")
    assert :ok = ObjectStorage.delete_object(os, "b", "k")
    assert {:error, :not_found} = ObjectStorage.get_object(os, "b", "k")
  end