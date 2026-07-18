    property "{:list, schema, opts} defaults length bounds to 0..10" do
      lengths =
        SchemaGenerators.from_schema({:list, :boolean, []})
        |> Enum.take(300)
        |> Enum.map(&length/1)

      assert Enum.all?(lengths, fn len -> len >= 0 and len <= 10 end)
      assert 0 in lengths
      assert 10 in lengths
    end