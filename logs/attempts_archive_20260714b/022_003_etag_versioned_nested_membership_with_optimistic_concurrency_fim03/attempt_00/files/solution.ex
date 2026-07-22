  # Interpret the header as an integer version. A non-integer value yields a
  # sentinel (-1) that can never match a real, non-negative version.
  @spec parse_version(String.t()) :: integer()
  defp parse_version(value) do
    case Integer.parse(String.trim(value)) do
      {version, ""} -> version
      _ -> -1
    end
  end