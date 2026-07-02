  test "an {:error, _} return marks failure and skips dependents" do
    ResilientRunner.submit(:runner, :a, func: fail_task(:a, :db_down))
    ResilientRunner.submit(:runner, :b, depends_on: [:a], func: ok_task(:b))

    assert {:ok, res} = ResilientRunner.run_all(:runner)
    assert res.failed == %{a: :db_down}
    assert res.skipped == [:b]
    assert res.completed == %{}
    refute Recorder.ran?(:b)
  end