  test "an empty bucket survives a restart", %{os: os, tmp_dir: tmp_dir} do
    VersionedObjectStorage.create_bucket(os, "kept")

    GenServer.stop(os)
    {:ok, pid2} = VersionedObjectStorage.start_link(root_dir: tmp_dir)

    assert {:ok, ["kept"]} = VersionedObjectStorage.list_buckets(pid2)
    assert {:ok, []} = VersionedObjectStorage.list_objects(pid2, "kept")
  end