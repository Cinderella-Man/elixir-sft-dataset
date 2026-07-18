  @spec format_stats(stats()) :: String.t()
  defp format_stats(%{total: t, inserted: i, invalid: inv, failed: f}) do
    "total=#{t} inserted=#{i} invalid=#{inv} failed=#{f}"
  end