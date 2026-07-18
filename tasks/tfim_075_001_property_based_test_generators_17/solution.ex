    property "start_date is always <= end_date" do
      check all(dr <- Generators.date_range()) do
        assert Date.compare(dr.start_date, dr.end_date) in [:lt, :eq]
      end
    end