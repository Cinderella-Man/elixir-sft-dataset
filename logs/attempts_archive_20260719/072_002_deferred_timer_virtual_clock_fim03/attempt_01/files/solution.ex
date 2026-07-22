    if is_atom(clock) do
      if function_exported?(clock, :now, 0) do
        clock.now()
      else
        Clock.Fake.now(clock)
      end
    else
      Clock.Fake.now(clock)
    end