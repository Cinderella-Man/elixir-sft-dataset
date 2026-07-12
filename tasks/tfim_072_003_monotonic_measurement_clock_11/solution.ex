    test "zero elapsed when the fake clock does not advance" do
      {:ok, c} = Clock.Fake.start_link(initial: 5000)
      {result, elapsed} = Clock.measure(c, fn -> 1 + 1 end)
      assert result == 2
      assert elapsed == 0
    end