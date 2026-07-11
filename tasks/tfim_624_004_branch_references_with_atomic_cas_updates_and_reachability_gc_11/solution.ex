  test "create_branch rejects an unknown commit", %{store: s} do
    assert {:error, :not_found} =
             ObjectStore.create_branch(s, "main", sha1("ghost"))
  end