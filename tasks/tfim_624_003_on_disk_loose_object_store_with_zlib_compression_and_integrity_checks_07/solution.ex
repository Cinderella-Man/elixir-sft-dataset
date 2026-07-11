  test "object is written at the documented fan-out path", %{store: s, dir: dir} do
    {:ok, hash} = ObjectStore.store(s, "layout check")
    assert File.exists?(object_path(dir, hash))
  end