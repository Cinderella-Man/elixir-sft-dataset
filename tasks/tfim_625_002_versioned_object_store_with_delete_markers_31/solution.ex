  test "start_link registers the process under the :name option", %{tmp_dir: tmp_dir} do
    name = :"vos_named_#{System.unique_integer([:positive])}"

    {:ok, _pid} =
      VersionedObjectStorage.start_link(root_dir: Path.join(tmp_dir, "named"), name: name)

    assert :ok = VersionedObjectStorage.create_bucket(name, "b")
    assert {:ok, _vid} = VersionedObjectStorage.put_object(name, "b", "k", "via-name")
    assert {:ok, ["b"]} = VersionedObjectStorage.list_buckets(name)
    assert {:ok, %{data: "via-name"}} = VersionedObjectStorage.get_object(name, "b", "k")
  end