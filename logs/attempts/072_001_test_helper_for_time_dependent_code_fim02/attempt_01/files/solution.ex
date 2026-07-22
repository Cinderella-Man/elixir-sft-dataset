    if is_atom(clock) and function_exported?(clock, :now, 0) do
      clock.now()            # module atom — e.g. Clock.Real
    else
      Clock.Fake.now(clock)  # registered-name atom or PID — e.g. :my_test_clock / pid
    end