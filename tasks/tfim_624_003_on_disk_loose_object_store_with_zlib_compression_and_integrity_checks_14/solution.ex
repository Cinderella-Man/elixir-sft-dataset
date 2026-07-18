  test "a second live process on the same directory sees objects written by the first", %{
    store: s,
    dir: dir
  } do
    {:ok, s2} = ObjectStore.start_link(dir: dir)

    {:ok, h1} = ObjectStore.store(s, "written by first")
    assert {:ok, "written by first"} = ObjectStore.retrieve(s2, h1)
    assert ObjectStore.has_object?(s2, h1) == true

    {:ok, h2} = ObjectStore.store(s2, "written by second")
    assert {:ok, "written by second"} = ObjectStore.retrieve(s, h2)
    assert ObjectStore.list_objects(s) == Enum.sort([h1, h2])

    :ok = GenServer.stop(s2)
  end