  test "pipeline with no stages returns input unchanged" do
    assert {:ok, 99, []} = Pipeline.run(Pipeline.new(), 99)
  end