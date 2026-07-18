    property "produces same-day ranges (start == end) and multi-day ranges" do
      comparisons =
        Enum.map(1..500, fn _ ->
          [dr] = Enum.take(Generators.date_range(), 1)
          Date.compare(dr.start_date, dr.end_date)
        end)

      assert :eq in comparisons, "Expected some same-day ranges"
      assert :lt in comparisons, "Expected some multi-day ranges"
    end