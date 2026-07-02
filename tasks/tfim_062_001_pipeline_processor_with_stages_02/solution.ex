  test "new/0 returns an empty pipeline" do
    pipeline = Pipeline.new()
    assert %Pipeline{} = pipeline
  end