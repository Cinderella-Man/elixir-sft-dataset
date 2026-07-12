    test "a weight of 0 means a generator is never selected" do
      gen =
        Generators.one_of_weighted([
          {0, StreamData.constant(:never)},
          {1, StreamData.constant(:always)}
        ])

      values = Enum.take(gen, 100)
      assert Enum.all?(values, &(&1 == :always))
    end