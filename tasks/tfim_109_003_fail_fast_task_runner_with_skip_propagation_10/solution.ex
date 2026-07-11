  test "detects a cycle and runs nothing" do
    ResilientRunner.submit(:runner, :a, depends_on: [:b], func: ok_task(:a))
    ResilientRunner.submit(:runner, :b, depends_on: [:a], func: ok_task(:b))

    assert {:error, {:cycle, involved}} = ResilientRunner.run_all(:runner)
    assert :a in involved and :b in involved
    assert Recorder.events() == []
  end