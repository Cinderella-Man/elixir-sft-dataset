    property "produces maps within the size bound" do
      check all(obj <- JsonGenerators.object(JsonGenerators.scalar(), 5)) do
        assert is_map(obj)
        assert map_size(obj) <= 5
      end
    end