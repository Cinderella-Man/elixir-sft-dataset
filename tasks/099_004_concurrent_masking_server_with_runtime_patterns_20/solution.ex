  @doc """
  Registers an additional masking pattern applied (in registration order) after
  the built-in patterns for every subsequent string scrubbed.
  """
  @spec add_pattern(server(), Regex.t(), String.t()) :: :ok
  def add_pattern(server, regex, replacement) do
    GenServer.call(server, {:add_pattern, regex, replacement})
  end