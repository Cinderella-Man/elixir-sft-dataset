  test "a raising task is captured as a failure, not re-raised" do
    ResilientRunner.submit(:runner, :a, func: raise_task(:a))
    ResilientRunner.submit(:runner, :b, depends_on: [:a], func: ok_task(:b))

    assert {:ok, res} = ResilientRunner.run_all(:runner)
    assert Map.has_key?(res.failed, :a)
    assert res.skipped == [:b]
    refute Recorder.ran?(:b)
  end