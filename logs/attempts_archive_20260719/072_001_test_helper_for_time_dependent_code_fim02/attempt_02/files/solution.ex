    if is_atom(clock) and function_exported?(clock, :now, 0) do
      clock.now()
    else
      Clock.Fake.now(clock)
    end