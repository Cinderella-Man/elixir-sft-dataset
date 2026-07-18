  test "each named store keeps its own independent object map" do
    name_a = unique_name("object_store_a")
    name_b = unique_name("object_store_b")
    {:ok, _a} = ObjectStore.start_link(name: name_a)
    {:ok, _b} = ObjectStore.start_link(name: name_b)

    {:ok, hash} = ObjectStore.store(name_a, "only in a")

    assert {:ok, "only in a"} = ObjectStore.retrieve(name_a, hash)
    assert {:error, :not_found} = ObjectStore.retrieve(name_b, hash)
  end