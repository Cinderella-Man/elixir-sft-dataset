    property "nested list-of-maps schema produces correctly nested values" do
      schema =
        {:list,
         {:map,
          %{
            tag: {:enum, ["x", "y", "z"]},
            score: {:integer, 0, 10}
          }}, [min: 0, max: 3]}

      check all(v <- SchemaGenerators.from_schema(schema)) do
        assert is_list(v)
        assert length(v) <= 3

        for row <- v do
          assert row.tag in ["x", "y", "z"]
          assert row.score >= 0 and row.score <= 10
        end
      end
    end