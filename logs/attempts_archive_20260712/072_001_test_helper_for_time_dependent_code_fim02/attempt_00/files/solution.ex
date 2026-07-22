  def now(clock) when is_atom(clock) do
    if function_exported?(clock, :now, 0) do
      clock.now()            # module atom — e.g. Clock.Real
    else
      Clock.Fake.now(clock)  # registered-name atom — e.g. :my_test_clock
    end
  end
  def now(clock), do: Clock.Fake.now(clock)