    property "produces diverse lengths across many samples" do
      lengths =
        Enum.map(1..200, fn _ ->
          [list] = Enum.take(Generators.non_empty_list(StreamData.integer()), 1)
          length(list)
        end)

      assert Enum.min(lengths) == 1
      assert Enum.max(lengths) > 1
    end