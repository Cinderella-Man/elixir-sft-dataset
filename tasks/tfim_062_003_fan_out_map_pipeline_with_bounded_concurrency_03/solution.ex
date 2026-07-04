  test "empty pipeline returns input unchanged" do
    assert {:ok, 5, []} = Pipeline.run(Pipeline.new(), 5)
  end