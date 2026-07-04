  test "empty pipeline returns input unchanged with empty metadata" do
    assert {:ok, 42, []} = Pipeline.run(Pipeline.new(), 42)
  end