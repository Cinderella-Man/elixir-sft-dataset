  test "detects a direct two-node cycle and reports it" do
    TaskRunner.submit(:runner, :a, depends_on: [:b], func: task(:a))
    TaskRunner.submit(:runner, :b, depends_on: [:a], func: task(:b))

    assert {:error, {:cycle, involved}} = TaskRunner.run_all(:runner)
    assert :a in involved
    assert :b in involved
  end