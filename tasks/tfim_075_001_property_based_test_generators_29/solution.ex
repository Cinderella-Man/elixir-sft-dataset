    property "date_range can be used inside a list_of" do
      check all(ranges <- StreamData.list_of(Generators.date_range(), length: 3)) do
        assert length(ranges) == 3

        for dr <- ranges do
          assert Date.compare(dr.start_date, dr.end_date) in [:lt, :eq]
        end
      end
    end