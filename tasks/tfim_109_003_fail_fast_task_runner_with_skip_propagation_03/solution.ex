  test "all-success DAG populates completed" do
    ResilientRunner.submit(:runner, :a, func: ok_task(:a, 0, 1))
    ResilientRunner.submit(:runner, :b, depends_on: [:a], func: ok_task(:b, 0, 2))
    ResilientRunner.submit(:runner, :c, depends_on: [:a], func: ok_task(:c, 0, 3))

    assert {:ok, res} = ResilientRunner.run_all(:runner)
    assert res.completed == %{a: 1, b: 2, c: 3}
    assert res.failed == %{}
    assert res.skipped == []
  end