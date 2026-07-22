  def now(clock) when is_atom(clock) do
    # ensure_loaded?/1 first: function_exported?/3 deliberately does NOT load
    # the module, so under lazy loading a real clock module's first use would
    # fall through to the Fake branch and exit :noproc.
    if Code.ensure_loaded?(clock) and function_exported?(clock, :now, 0) do
      clock.now()
    else
      Clock.Fake.now(clock)
    end
  end

  def now(clock), do: Clock.Fake.now(clock)