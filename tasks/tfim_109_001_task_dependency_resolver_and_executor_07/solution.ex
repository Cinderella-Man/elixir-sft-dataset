  test "long dependency chain executes strictly in order" do
    TaskRunner.submit(:runner, :t1, func: task(:t1, 10))
    TaskRunner.submit(:runner, :t2, depends_on: [:t1], func: task(:t2, 10))
    TaskRunner.submit(:runner, :t3, depends_on: [:t2], func: task(:t3, 10))
    TaskRunner.submit(:runner, :t4, depends_on: [:t3], func: task(:t4, 10))

    assert {:ok, %{t1: :t1, t2: :t2, t3: :t3, t4: :t4}} =
             TaskRunner.run_all(:runner)

    assert Recorder.ended_at(:t1) <= Recorder.started_at(:t2)
    assert Recorder.ended_at(:t2) <= Recorder.started_at(:t3)
    assert Recorder.ended_at(:t3) <= Recorder.started_at(:t4)
  end