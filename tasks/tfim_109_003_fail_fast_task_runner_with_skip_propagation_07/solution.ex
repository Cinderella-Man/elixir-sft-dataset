  test "an unrelated sibling branch still completes when another fails" do
    ResilientRunner.submit(:runner, :a, func: fail_task(:a))
    ResilientRunner.submit(:runner, :b, depends_on: [:a], func: ok_task(:b))
    ResilientRunner.submit(:runner, :x, func: ok_task(:x, 0, :x_val))
    ResilientRunner.submit(:runner, :y, depends_on: [:x], func: ok_task(:y, 0, :y_val))

    assert {:ok, res} = ResilientRunner.run_all(:runner)
    assert res.completed == %{x: :x_val, y: :y_val}
    assert Map.has_key?(res.failed, :a)
    assert res.skipped == [:b]
  end