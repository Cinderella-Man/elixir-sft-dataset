  test "the file contents are zlib-compressed raw bytes", %{store: s, dir: dir} do
    content = "compress me please"
    {:ok, hash} = ObjectStore.store(s, content)
    raw = File.read!(object_path(dir, hash))
    assert :zlib.uncompress(raw) == content
  end