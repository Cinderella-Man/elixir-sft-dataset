  test "skip propagates transitively down a chain" do
    ResilientRunner.submit(:runner, :a, func: fail_task(:a))
    ResilientRunner.submit(:runner, :b, depends_on: [:a], func: ok_task(:b))
    ResilientRunner.submit(:runner, :c, depends_on: [:b], func: ok_task(:c))

    assert {:ok, res} = ResilientRunner.run_all(:runner)
    assert Map.has_key?(res.failed, :a)
    assert Enum.sort(res.skipped) == [:b, :c]
    refute Recorder.ran?(:b)
    refute Recorder.ran?(:c)
  end