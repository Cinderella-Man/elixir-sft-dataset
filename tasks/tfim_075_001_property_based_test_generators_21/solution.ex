    property "never produces a list with more than 20 elements" do
      check all(list <- Generators.non_empty_list(StreamData.integer())) do
        assert length(list) <= 20
      end
    end