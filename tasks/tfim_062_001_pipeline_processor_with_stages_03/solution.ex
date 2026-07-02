  test "stage/3 returns a Pipeline struct" do
    pipeline = Pipeline.new() |> Pipeline.stage(:first, ok_stage(& &1))
    assert %Pipeline{} = pipeline
  end