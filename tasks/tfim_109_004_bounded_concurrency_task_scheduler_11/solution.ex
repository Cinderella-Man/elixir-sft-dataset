  test "reports unknown dependencies and runs nothing" do
    start_runner(2)
    BoundedRunner.submit(:runner, :b, depends_on: [:ghost], func: task(:b))

    assert {:error, {:unknown_dependencies, missing}} = BoundedRunner.run_all(:runner)
    assert :ghost in missing
    assert Tracker.events() == []
  end