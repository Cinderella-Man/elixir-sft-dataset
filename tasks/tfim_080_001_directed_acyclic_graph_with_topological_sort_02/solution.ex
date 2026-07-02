  test "new/0 returns an empty DAG" do
    dag = DAG.new()
    assert {:ok, []} = DAG.topological_sort(dag)
  end