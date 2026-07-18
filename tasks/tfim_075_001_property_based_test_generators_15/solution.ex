    property "always produces a map with :start_date and :end_date" do
      check all(dr <- Generators.date_range()) do
        assert Map.has_key?(dr, :start_date)
        assert Map.has_key?(dr, :end_date)
      end
    end