  test "a task that merely depends on a cycle is not reported as involved" do
    TaskRunner.submit(:runner, :a, depends_on: [:b], func: task(:a))
    TaskRunner.submit(:runner, :b, depends_on: [:a], func: task(:b))
    TaskRunner.submit(:runner, :c, depends_on: [:a], func: task(:c))

    assert {:error, {:cycle, involved}} = TaskRunner.run_all(:runner)
    assert :a in involved
    assert :b in involved
    refute :c in involved
  end