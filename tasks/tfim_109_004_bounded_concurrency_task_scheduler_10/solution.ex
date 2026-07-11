  test "detects a cycle and runs nothing" do
    start_runner(2)
    BoundedRunner.submit(:runner, :a, depends_on: [:b], func: task(:a))
    BoundedRunner.submit(:runner, :b, depends_on: [:a], func: task(:b))

    assert {:error, {:cycle, involved}} = BoundedRunner.run_all(:runner)
    assert :a in involved and :b in involved
    assert Tracker.events() == []
  end