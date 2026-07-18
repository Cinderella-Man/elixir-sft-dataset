  @spec parse_integer(binary()) :: {:ok, integer()} | :error
  defp parse_integer(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _other -> :error
    end
  end