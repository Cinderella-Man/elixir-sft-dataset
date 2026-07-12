    property "produces lists within the length bound" do
      check all(list <- JsonGenerators.array(JsonGenerators.scalar(), 5)) do
        assert is_list(list)
        assert length(list) <= 5
      end
    end