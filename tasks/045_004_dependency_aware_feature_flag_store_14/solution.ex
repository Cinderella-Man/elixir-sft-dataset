  defp eval({:on}, _flag, _user), do: true
  defp eval({:off}, _flag, _user), do: false
  defp eval({:percentage, pct}, flag, user), do: :erlang.phash2({flag, user}, 100) < pct