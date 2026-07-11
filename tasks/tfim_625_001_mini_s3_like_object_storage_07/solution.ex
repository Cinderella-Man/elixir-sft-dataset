  test "delete a non-existent bucket returns error", %{os: os} do
    assert {:error, :not_found} = ObjectStorage.delete_bucket(os, "ghost")
  end