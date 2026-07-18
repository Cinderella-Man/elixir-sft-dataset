  test "map stage with non-list input raises ArgumentError" do
    pipeline = Pipeline.new() |> Pipeline.map_stage(:m, fn x -> {:ok, x} end)

    assert_raise ArgumentError, fn ->
      Pipeline.run(pipeline, :not_a_list)
    end
  end