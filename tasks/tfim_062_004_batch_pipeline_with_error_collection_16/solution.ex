  test "run/2 rejects inputs that are not a list" do
    pipeline = Pipeline.new() |> Pipeline.stage(:noop, ok_stage(& &1))

    assert_raise FunctionClauseError, fn -> Pipeline.run(pipeline, :not_a_list) end
  end