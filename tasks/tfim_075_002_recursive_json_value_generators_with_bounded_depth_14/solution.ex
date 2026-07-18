    property "all values come from the inner generator" do
      check all(obj <- JsonGenerators.object(StreamData.boolean(), 5)) do
        assert Enum.all?(Map.values(obj), &is_boolean/1)
      end
    end