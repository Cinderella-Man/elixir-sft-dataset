  @doc """
  Return a map describing the current state of the pool:

      %{available: a, in_use: u, total: t, max: max, min: min}

  where `total == a + u`.
  """
  def stats(name) do
    GenServer.call(name, :stats)
  end