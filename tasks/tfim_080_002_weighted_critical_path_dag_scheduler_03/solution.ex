  test "add_task/3 ignores duplicates and keeps original duration" do
    dag =
      WeightedDAG.new()
      |> WeightedDAG.add_task(:a, 5)
      |> WeightedDAG.add_task(:a, 99)

    {:ok, ef} = WeightedDAG.earliest_finish(dag)
    assert ef == %{a: 5}
  end