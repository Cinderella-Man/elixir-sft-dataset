  test "empty runner returns an empty map" do
    start_runner(2)
    assert {:ok, %{}} = BoundedRunner.run_all(:runner)
  end