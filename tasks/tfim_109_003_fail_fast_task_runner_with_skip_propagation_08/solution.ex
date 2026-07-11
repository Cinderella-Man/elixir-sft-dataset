  test "diamond: one failing parent skips only the join, other parent completes" do
    #      a
    #     / \
    #    b   c    (b fails)
    #     \ /
    #      d
    ResilientRunner.submit(:runner, :a, func: ok_task(:a, 0, :a))
    ResilientRunner.submit(:runner, :b, depends_on: [:a], func: fail_task(:b))
    ResilientRunner.submit(:runner, :c, depends_on: [:a], func: ok_task(:c, 0, :c))
    ResilientRunner.submit(:runner, :d, depends_on: [:b, :c], func: ok_task(:d))

    assert {:ok, res} = ResilientRunner.run_all(:runner)
    assert res.completed == %{a: :a, c: :c}
    assert Map.has_key?(res.failed, :b)
    assert res.skipped == [:d]
    refute Recorder.ran?(:d)
  end