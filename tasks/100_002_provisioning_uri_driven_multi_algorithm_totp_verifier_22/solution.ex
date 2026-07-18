  @doc """
  Returns the number of seconds the code current at `unix_time` remains valid.

  On an exact period boundary this returns the full period.
  """
  @spec seconds_remaining(t(), integer()) :: number()
  def seconds_remaining(config, unix_time) when is_integer(unix_time) do
    config.period - rem(unix_time, config.period)
  end