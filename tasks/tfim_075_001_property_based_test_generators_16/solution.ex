    property "start_date and end_date are always Date structs" do
      check all(dr <- Generators.date_range()) do
        assert %Date{} = dr.start_date
        assert %Date{} = dr.end_date
      end
    end