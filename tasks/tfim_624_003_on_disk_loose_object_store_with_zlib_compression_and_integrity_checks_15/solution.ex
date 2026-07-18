  test "start_link creates the object directory when it does not exist", %{dir: dir} do
    nested = Path.join([dir, "not", "yet", "created"])
    refute File.exists?(nested)

    {:ok, s2} = ObjectStore.start_link(dir: nested)
    assert File.dir?(nested)

    {:ok, hash} = ObjectStore.store(s2, "fresh dir")
    assert File.exists?(object_path(nested, hash))
    assert ObjectStore.list_objects(s2) == [hash]

    :ok = GenServer.stop(s2)
  end