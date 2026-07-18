  test "an exit with reason :normal is still captured and tagged" do
    results = WorkStealQueue.run([1, 2], 2, fn _ -> exit(:normal) end)

    assert length(results) == 2

    for %{result: result} <- results do
      assert result == {:error, %{kind: :exit, reason: :normal}}
    end
  end