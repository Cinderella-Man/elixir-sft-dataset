  test "detects a cycle and runs nothing" do
    DataFlowRunner.submit(:runner, :a, depends_on: [:b], func: rec(:a, 0, fn _ -> 1 end))
    DataFlowRunner.submit(:runner, :b, depends_on: [:a], func: rec(:b, 0, fn _ -> 2 end))

    assert {:error, {:cycle, involved}} = DataFlowRunner.run_all(:runner)
    assert :a in involved and :b in involved
    assert Recorder.events() == []
  end