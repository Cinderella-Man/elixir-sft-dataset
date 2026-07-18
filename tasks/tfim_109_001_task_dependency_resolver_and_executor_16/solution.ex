  test "submitting the same task_id again overwrites the definition" do
    TaskRunner.submit(:runner, :a, func: task(:a, 0, :first))
    TaskRunner.submit(:runner, :a, func: task(:a, 0, :second))

    assert {:ok, %{a: :second}} = TaskRunner.run_all(:runner)
  end