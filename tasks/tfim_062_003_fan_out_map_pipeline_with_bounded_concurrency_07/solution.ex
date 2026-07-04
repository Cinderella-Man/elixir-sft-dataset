  test "map stage fails on the first failing element by index" do
    fail_on_three = fn x -> if x == 3, do: {:error, :three}, else: {:ok, x} end

    pipeline = Pipeline.new() |> Pipeline.map_stage(:check, fail_on_three)

    assert {:error, :check, :three} = Pipeline.run(pipeline, [1, 2, 3, 4])
  end