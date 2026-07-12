    property "produces empty and non-empty lists across samples" do
      lengths =
        Enum.map(1..300, fn _ ->
          [list] = Enum.take(JsonGenerators.array(JsonGenerators.scalar(), 5), 1)
          length(list)
        end)

      assert Enum.min(lengths) == 0
      assert Enum.max(lengths) > 0
    end