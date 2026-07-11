  test "a long chain accumulates results in order" do
    DataFlowRunner.submit(:runner, :t1, func: fn _ -> 1 end)
    DataFlowRunner.submit(:runner, :t2, depends_on: [:t1], func: fn %{t1: v} -> v + 1 end)
    DataFlowRunner.submit(:runner, :t3, depends_on: [:t2], func: fn %{t2: v} -> v + 1 end)
    DataFlowRunner.submit(:runner, :t4, depends_on: [:t3], func: fn %{t3: v} -> v + 1 end)

    assert {:ok, %{t1: 1, t2: 2, t3: 3, t4: 4}} = DataFlowRunner.run_all(:runner)
  end