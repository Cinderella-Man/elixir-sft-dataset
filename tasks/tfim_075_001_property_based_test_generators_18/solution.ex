    property "dates are always within the allowed range" do
      min = ~D[2000-01-01]
      max = ~D[2100-12-31]

      check all(dr <- Generators.date_range()) do
        assert Date.compare(dr.start_date, min) in [:gt, :eq]
        assert Date.compare(dr.end_date, max) in [:lt, :eq]
      end
    end