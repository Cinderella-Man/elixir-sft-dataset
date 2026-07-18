  test "map stage reports the earliest failing element when several elements fail" do
    fun = fn
      1 -> {:error, :first}
      3 -> {:error, :third}
      x -> {:ok, x}
    end

    pipeline = Pipeline.new() |> Pipeline.map_stage(:pick, fun)

    assert {:error, :pick, :first} = Pipeline.run(pipeline, [0, 1, 2, 3])
  end