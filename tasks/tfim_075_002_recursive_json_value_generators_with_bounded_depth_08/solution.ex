    property "produces diverse scalar kinds across many samples" do
      kinds =
        Enum.map(1..400, fn _ ->
          [v] = Enum.take(JsonGenerators.scalar(), 1)

          cond do
            is_nil(v) -> :null
            is_boolean(v) -> :bool
            is_integer(v) -> :int
            is_binary(v) -> :string
          end
        end)

      assert :null in kinds
      assert :bool in kinds
      assert :int in kinds
      assert :string in kinds
    end