    property "always produces a list with at least one element" do
      check all(list <- Generators.non_empty_list(StreamData.integer())) do
        assert is_list(list)
        assert length(list) >= 1
      end
    end