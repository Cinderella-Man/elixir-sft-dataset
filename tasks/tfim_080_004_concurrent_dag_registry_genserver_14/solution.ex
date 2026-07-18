  test "start_link forwards opts so the server is reachable by registered name" do
    name = :dag_server_named_opts_test

    assert {:ok, pid} = DAGServer.start_link(name: name)
    assert is_pid(pid)
    assert Process.whereis(name) == pid

    assert :ok = DAGServer.add_vertex(name, :x)
    assert :ok = DAGServer.add_vertex(name, :y)
    assert :ok = DAGServer.add_edge(name, :x, :y)
    assert {:ok, [:x, :y]} = DAGServer.topological_sort(name)
    assert DAGServer.successors(name, :x) == [:y]
  end