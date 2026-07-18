  test "copy to same bucket and same key is a no-op success", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    ObjectStorage.put_object(os, "b", "k", "original")

    assert :ok = ObjectStorage.copy_object(os, "b", "k", "b", "k")
    assert {:ok, %{data: "original"}} = ObjectStorage.get_object(os, "b", "k")
  end