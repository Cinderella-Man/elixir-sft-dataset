  @doc """
  Returns cumulative masking statistics since the server started:
  `%{keys_masked: k, patterns_applied: p}`.
  """
  @spec stats(server()) :: stats()
  def stats(server) do
    GenServer.call(server, :stats)
  end