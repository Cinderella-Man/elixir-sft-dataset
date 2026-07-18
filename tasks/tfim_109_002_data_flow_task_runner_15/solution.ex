  test "submitting alone executes nothing before run_all is called" do
    DataFlowRunner.submit(:runner, :s1, func: rec(:s1, 0, fn _ -> 1 end))

    DataFlowRunner.submit(:runner, :s2,
      depends_on: [:s1],
      func: rec(:s2, 0, fn %{s1: v} -> v end)
    )

    assert Recorder.events() == []

    assert {:ok, %{s1: 1, s2: 1}} = DataFlowRunner.run_all(:runner)
    assert Recorder.started_at(:s1) != nil
  end