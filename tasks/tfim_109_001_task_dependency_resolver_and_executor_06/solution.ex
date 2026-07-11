  test "a task waits for ALL of its dependencies (diamond DAG)" do
    #      a
    #     / \
    #    b   c
    #     \ /
    #      d
    TaskRunner.submit(:runner, :a, func: task(:a, 40))
    TaskRunner.submit(:runner, :b, depends_on: [:a], func: task(:b, 120))
    TaskRunner.submit(:runner, :c, depends_on: [:a], func: task(:c, 120))
    TaskRunner.submit(:runner, :d, depends_on: [:b, :c], func: task(:d, 20))

    assert {:ok, _} = TaskRunner.run_all(:runner)

    # b and c start only after a finishes
    assert Recorder.ended_at(:a) <= Recorder.started_at(:b)
    assert Recorder.ended_at(:a) <= Recorder.started_at(:c)

    # d starts only after BOTH b and c finish
    assert Recorder.ended_at(:b) <= Recorder.started_at(:d)
    assert Recorder.ended_at(:c) <= Recorder.started_at(:d)
  end