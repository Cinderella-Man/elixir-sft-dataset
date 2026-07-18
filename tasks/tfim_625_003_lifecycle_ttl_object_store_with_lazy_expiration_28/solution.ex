  test "the server can be registered and addressed by name", %{os: _os} do
    name = :"ttl_named_#{System.unique_integer([:positive])}"
    {:ok, pid} = TtlObjectStorage.start_link(name: name)
    assert :ok = TtlObjectStorage.create_bucket(name, "b")
    :ok = TtlObjectStorage.put_object(name, "b", "k", "v")

    assert {:ok, %{data: "v"}} =
             TtlObjectStorage.get_object(name, "k" |> then(fn _ -> "b" end), "k")

    GenServer.stop(pid)
  end