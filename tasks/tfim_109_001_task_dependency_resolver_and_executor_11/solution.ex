  test "detects a larger cycle" do
    TaskRunner.submit(:runner, :a, depends_on: [:c], func: task(:a))
    TaskRunner.submit(:runner, :b, depends_on: [:a], func: task(:b))
    TaskRunner.submit(:runner, :c, depends_on: [:b], func: task(:c))

    assert {:error, {:cycle, _involved}} = TaskRunner.run_all(:runner)
  end