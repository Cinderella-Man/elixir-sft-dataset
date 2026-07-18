  test "resubmitting a task overwrites its definition" do
    start_runner(2)
    BoundedRunner.submit(:runner, :a, func: task(:a, 0, :first))
    BoundedRunner.submit(:runner, :a, func: task(:a, 0, :second))

    assert {:ok, %{a: :second}} = BoundedRunner.run_all(:runner)
  end