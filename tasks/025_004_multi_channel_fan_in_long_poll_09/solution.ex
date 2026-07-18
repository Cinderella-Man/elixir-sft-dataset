  @spec parse_channels(String.t() | nil) :: [String.t()]
  defp parse_channels(nil), do: []
  defp parse_channels(str), do: String.split(str, ",", trim: true)