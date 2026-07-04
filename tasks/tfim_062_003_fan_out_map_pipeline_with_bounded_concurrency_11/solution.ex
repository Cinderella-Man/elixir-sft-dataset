  test "map stage on empty list yields empty output" do
    pipeline = Pipeline.new() |> Pipeline.map_stage(:m, fn x -> {:ok, x} end)
    assert {:ok, [], [%{stage: :m, type: :map, count: 0}]} = Pipeline.run(pipeline, [])
  end