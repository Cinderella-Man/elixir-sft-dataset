  test "reports unknown dependencies and runs nothing" do
    ResilientRunner.submit(:runner, :b, depends_on: [:ghost], func: ok_task(:b))

    assert {:error, {:unknown_dependencies, missing}} = ResilientRunner.run_all(:runner)
    assert :ghost in missing
    assert Recorder.events() == []
  end