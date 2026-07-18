  test "a self-dependency is a cycle" do
    TaskRunner.submit(:runner, :a, depends_on: [:a], func: task(:a))

    assert {:error, {:cycle, _}} = TaskRunner.run_all(:runner)
  end