  test "each put creates a new retained version; get returns the newest", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    {:ok, vid1} = VersionedObjectStorage.put_object(os, "b", "k", "one")
    {:ok, vid2} = VersionedObjectStorage.put_object(os, "b", "k", "two")

    assert vid1 != vid2

    assert {:ok, %{data: "two", version_id: ^vid2}} =
             VersionedObjectStorage.get_object(os, "b", "k")

    assert {:ok, versions} = VersionedObjectStorage.list_versions(os, "b", "k")
    assert length(versions) == 2

    # newest first
    assert [%{version_id: ^vid2, is_delete_marker: false} | _] = versions
  end