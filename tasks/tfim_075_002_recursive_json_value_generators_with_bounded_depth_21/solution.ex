    property "value can be nested inside list_of" do
      check all(list <- StreamData.list_of(JsonGenerators.value(2), length: 3)) do
        assert length(list) == 3
        assert Enum.all?(list, fn v -> depth(v) <= 2 end)
      end
    end