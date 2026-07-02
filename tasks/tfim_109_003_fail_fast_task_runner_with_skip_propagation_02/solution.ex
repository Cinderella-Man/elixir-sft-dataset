  test "empty runner returns empty completed/failed/skipped" do
    assert {:ok, %{completed: %{}, failed: %{}, skipped: []}} =
             ResilientRunner.run_all(:runner)
  end