  test "the failure reason term is returned verbatim regardless of its shape" do
    reason = {:http, 500, %{body: "boom", retries: [1, 2]}}

    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:fetch, fn _ -> {:error, reason} end)

    assert {:error, :fetch, ^reason} = Pipeline.run(pipeline, :input)
  end