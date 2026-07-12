  test "retrieve returns corrupt when the hash does not match", %{store: s, dir: dir} do
    hash_a = sha1("content A")
    path = object_path(dir, hash_a)
    File.mkdir_p!(Path.dirname(path))
    # Store the compressed bytes of a DIFFERENT content under hash_a's path.
    File.write!(path, :zlib.compress("content B"))
    assert {:error, :corrupt} = ObjectStore.retrieve(s, hash_a)
  end