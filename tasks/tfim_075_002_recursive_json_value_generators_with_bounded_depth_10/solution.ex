    property "all elements come from the inner generator" do
      check all(list <- JsonGenerators.array(StreamData.integer(), 6)) do
        assert Enum.all?(list, &is_integer/1)
      end
    end