  test "metadata and version ids survive a restart", %{os: os, tmp_dir: tmp_dir} do
    VersionedObjectStorage.create_bucket(os, "meta")
    {:ok, vid} = VersionedObjectStorage.put_object(os, "meta", "k", "body", %{"a" => "b"})

    GenServer.stop(os)
    {:ok, pid2} = VersionedObjectStorage.start_link(root_dir: tmp_dir)

    assert {:ok, obj} = VersionedObjectStorage.get_object(pid2, "meta", "k")
    assert obj.version_id == vid
    assert obj.metadata == %{"a" => "b"}
    assert obj.data == "body"
  end