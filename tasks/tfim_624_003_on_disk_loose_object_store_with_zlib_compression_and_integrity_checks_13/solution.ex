  test "objects persist to a new process using the same directory", %{store: s, dir: dir} do
    {:ok, h1} = ObjectStore.store(s, "persist one")
    {:ok, h2} = ObjectStore.store(s, "persist two")
    :ok = GenServer.stop(s)

    {:ok, s2} = ObjectStore.start_link(dir: dir)
    assert {:ok, "persist one"} = ObjectStore.retrieve(s2, h1)
    assert {:ok, "persist two"} = ObjectStore.retrieve(s2, h2)
    assert ObjectStore.list_objects(s2) == Enum.sort([h1, h2])
  end