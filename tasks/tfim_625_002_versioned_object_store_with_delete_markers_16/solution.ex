  test "delete_object writes a delete marker and hides the object", %{os: os} do
    VersionedObjectStorage.create_bucket(os, "b")
    {:ok, _} = VersionedObjectStorage.put_object(os, "b", "k", "one")

    assert {:ok, marker} = VersionedObjectStorage.delete_object(os, "b", "k")
    assert is_binary(marker)

    assert {:error, :not_found} = VersionedObjectStorage.get_object(os, "b", "k")

    assert {:ok, versions} = VersionedObjectStorage.list_versions(os, "b", "k")
    assert length(versions) == 2
    assert [%{version_id: ^marker, is_delete_marker: true, size: 0} | _] = versions

    assert {:ok, %{is_delete_marker: true, data: ""}} =
             VersionedObjectStorage.get_object_version(os, "b", "k", marker)
  end