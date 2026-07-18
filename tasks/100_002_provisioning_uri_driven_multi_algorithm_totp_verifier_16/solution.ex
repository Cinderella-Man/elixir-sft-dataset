  @spec parse_period(map()) :: {:ok, pos_integer()} | {:error, :invalid_period}
  defp parse_period(params) do
    raw = Map.get(params, "period", "30")

    case Integer.parse(raw) do
      {period, ""} when period > 0 -> {:ok, period}
      _other -> {:error, :invalid_period}
    end
  end