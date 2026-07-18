    property "only produces values from the given generators" do
      gen =
        Generators.one_of_weighted([
          {1, StreamData.constant(:rare)},
          {9, StreamData.constant(:common)}
        ])

      check all(value <- gen) do
        assert value in [:rare, :common]
      end
    end