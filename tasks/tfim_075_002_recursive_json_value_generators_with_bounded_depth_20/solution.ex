    property "produces scalars, arrays, and objects across many samples" do
      kinds =
        Enum.map(1..500, fn _ ->
          [v] = Enum.take(JsonGenerators.value(3), 1)

          cond do
            is_list(v) -> :array
            is_map(v) -> :object
            true -> :scalar
          end
        end)

      assert :scalar in kinds
      assert :array in kinds
      assert :object in kinds
    end