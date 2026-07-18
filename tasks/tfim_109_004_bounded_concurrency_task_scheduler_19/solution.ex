  test "resubmitting replaces the previous dependency list" do
    start_runner(2)
    BoundedRunner.submit(:runner, :solo, depends_on: [:ghost], func: task(:solo, 0, :one))
    BoundedRunner.submit(:runner, :solo, func: task(:solo, 0, :two))

    assert {:ok, %{solo: :two}} = BoundedRunner.run_all(:runner)
  end