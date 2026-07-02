  test "single task returns its value" do
    start_runner(2)
    BoundedRunner.submit(:runner, :a, func: task(:a, 0, 42))
    assert {:ok, %{a: 42}} = BoundedRunner.run_all(:runner)
  end