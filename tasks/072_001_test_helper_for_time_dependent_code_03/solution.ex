  def now(clock) when is_atom(clock) do
    if function_exported?(clock, :now, 0) do
      # module atom — e.g. Clock.Real
      clock.now()
    else
      # registered-name atom — e.g. :my_test_clock
      Clock.Fake.now(clock)
    end
  end

  def now(clock), do: Clock.Fake.now(clock)
