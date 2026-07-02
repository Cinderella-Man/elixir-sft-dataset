  test "results are keyed by task_id for a whole DAG" do
    TaskRunner.submit(:runner, :a, func: task(:a, 0, 1))
    TaskRunner.submit(:runner, :b, depends_on: [:a], func: task(:b, 0, 2))
    TaskRunner.submit(:runner, :c, depends_on: [:a], func: task(:c, 0, 3))
    TaskRunner.submit(:runner, :d, depends_on: [:b, :c], func: task(:d, 0, 4))

    assert {:ok, results} = TaskRunner.run_all(:runner)
    assert results == %{a: 1, b: 2, c: 3, d: 4}
  end