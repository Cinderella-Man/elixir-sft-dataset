  def date_range do
    min_day = Date.to_gregorian_days(~D[2000-01-01])
    max_day = Date.to_gregorian_days(~D[2100-12-31])

    SD.bind(SD.integer(min_day..max_day), fn start_day ->
      # Use one_of to split between two explicit branches:
      #   1. same-day (start == end) — guaranteed to appear in every test run
      #   2. any valid end-day in [start_day, max_day] — covers multi-day ranges
      # Relying on bias alone (e.g. integer(0..36524) happening to pick 0) is
      # too probabilistic; with 100 default runs it fails intermittently.
      same_day = SD.constant(start_day)
      any_day = SD.integer(start_day..max_day)

      SD.bind(SD.one_of([same_day, any_day]), fn end_day ->
        SD.constant(%{
          start_date: Date.from_gregorian_days(start_day),
          end_date: Date.from_gregorian_days(end_day)
        })
      end)
    end)
  end