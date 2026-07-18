  test "delete from non-existent bucket returns error", %{os: os} do
    assert {:error, :bucket_not_found} = ObjectStorage.delete_object(os, "nope", "k")
  end