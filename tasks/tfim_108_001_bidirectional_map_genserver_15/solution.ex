  test "start_link with a :name option returns {:ok, pid} and registers that name" do
    name = :"bimap_started_#{System.unique_integer([:positive])}"

    assert {:ok, pid} = BiMap.start_link(name: name)
    assert is_pid(pid)
    assert Process.whereis(name) == pid

    assert :ok = BiMap.put(name, :k, :v)
    assert {:ok, :v} = BiMap.get_by_key(name, :k)

    GenServer.stop(pid)
  end