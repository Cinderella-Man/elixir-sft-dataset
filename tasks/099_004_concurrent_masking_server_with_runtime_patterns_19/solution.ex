  @doc """
  Scans a raw string and masks the built-in patterns plus any registered custom
  patterns, returning the scrubbed string.
  """
  @spec mask_string(server(), String.t()) :: String.t()
  def mask_string(server, string) do
    GenServer.call(server, {:mask_string, string})
  end