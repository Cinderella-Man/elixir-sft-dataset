  test "delete is idempotent — deleting a missing key succeeds", %{os: os} do
    ObjectStorage.create_bucket(os, "b")
    assert :ok = ObjectStorage.delete_object(os, "b", "never-existed")
  end