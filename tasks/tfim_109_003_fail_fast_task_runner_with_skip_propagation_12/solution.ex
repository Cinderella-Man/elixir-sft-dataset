  test "resubmitting a task overwrites its definition" do
    ResilientRunner.submit(:runner, :a, func: ok_task(:a, 0, :first))
    ResilientRunner.submit(:runner, :a, func: ok_task(:a, 0, :second))

    assert {:ok, %{completed: %{a: :second}}} = ResilientRunner.run_all(:runner)
  end