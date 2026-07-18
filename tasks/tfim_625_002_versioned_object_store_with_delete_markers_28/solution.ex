  test "versions and restore survive a restart", %{os: os, tmp_dir: tmp_dir} do
    VersionedObjectStorage.create_bucket(os, "persist")
    {:ok, _} = VersionedObjectStorage.put_object(os, "persist", "k", "one", %{"x" => "y"})
    {:ok, _} = VersionedObjectStorage.put_object(os, "persist", "k", "two")
    {:ok, marker} = VersionedObjectStorage.delete_object(os, "persist", "k")

    GenServer.stop(os)
    {:ok, pid2} = VersionedObjectStorage.start_link(root_dir: tmp_dir)

    assert {:ok, ["persist"]} = VersionedObjectStorage.list_buckets(pid2)
    assert {:error, :not_found} = VersionedObjectStorage.get_object(pid2, "persist", "k")

    assert {:ok, versions} = VersionedObjectStorage.list_versions(pid2, "persist", "k")
    assert length(versions) == 3
    assert [%{is_delete_marker: true} | _] = versions

    assert :ok = VersionedObjectStorage.delete_version(pid2, "persist", "k", marker)
    assert {:ok, %{data: "two"}} = VersionedObjectStorage.get_object(pid2, "persist", "k")
  end