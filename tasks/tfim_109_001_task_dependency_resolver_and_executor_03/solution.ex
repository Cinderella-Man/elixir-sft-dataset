  test "runs a single task with no dependencies and returns its value" do
    assert :ok = TaskRunner.submit(:runner, :a, func: task(:a, 0, 42))

    assert {:ok, results} = TaskRunner.run_all(:runner)
    assert results == %{a: 42}
  end