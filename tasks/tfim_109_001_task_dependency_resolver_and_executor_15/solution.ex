  test "does not execute any task when a dependency is unknown" do
    TaskRunner.submit(:runner, :real, func: task(:real))
    TaskRunner.submit(:runner, :b, depends_on: [:ghost], func: task(:b))

    assert {:error, {:unknown_dependencies, missing}} =
             TaskRunner.run_all(:runner)

    assert :ghost in missing
    assert Recorder.events() == []
  end