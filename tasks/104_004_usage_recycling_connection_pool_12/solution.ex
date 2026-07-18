  defp retire?(_count, :infinity), do: false
  defp retire?(count, max_uses) when is_integer(max_uses), do: count >= max_uses