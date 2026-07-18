  test "a cycle prevents even independent tasks from running" do
    start_runner(2)
    BoundedRunner.submit(:runner, :free, func: task(:free))
    BoundedRunner.submit(:runner, :x, depends_on: [:y], func: task(:x))
    BoundedRunner.submit(:runner, :y, depends_on: [:x], func: task(:y))

    assert {:error, {:cycle, involved}} = BoundedRunner.run_all(:runner)
    assert :x in involved and :y in involved
    assert Tracker.events() == []
  end