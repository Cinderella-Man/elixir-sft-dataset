  test "no task executes when a cycle is present" do
    TaskRunner.submit(:runner, :a, depends_on: [:b], func: task(:a))
    TaskRunner.submit(:runner, :b, depends_on: [:a], func: task(:b))

    assert {:error, {:cycle, _}} = TaskRunner.run_all(:runner)
    assert Recorder.events() == []
  end