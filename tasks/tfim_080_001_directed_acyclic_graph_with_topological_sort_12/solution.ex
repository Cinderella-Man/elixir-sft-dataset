  test "topological sort is valid for a known dependency graph" do
    # Simulates: mix -> hex -> ssl -> crypto
    #                        -> public_key -> crypto
    vertices = [:mix, :hex, :ssl, :crypto, :public_key]

    edges = [
      {:mix, :hex},
      {:hex, :ssl},
      {:ssl, :crypto},
      {:ssl, :public_key},
      {:public_key, :crypto}
    ]

    dag = Enum.reduce(vertices, DAG.new(), &DAG.add_vertex(&2, &1))

    dag =
      Enum.reduce(edges, dag, fn {from, to}, acc ->
        {:ok, updated} = DAG.add_edge(acc, from, to)
        updated
      end)

    assert {:ok, order} = DAG.topological_sort(dag)
    assert valid_topological_order?(order, edges)
    assert length(order) == length(vertices)
  end