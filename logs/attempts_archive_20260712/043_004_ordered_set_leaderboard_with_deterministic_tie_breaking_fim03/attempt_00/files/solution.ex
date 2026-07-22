  defp take_first(_tid, :"$end_of_table", _n, acc), do: Enum.reverse(acc)
  defp take_first(_tid, _key, 0, acc), do: Enum.reverse(acc)

  defp take_first(tid, key, n, acc) do
    [{^key, player_id, score}] = :ets.lookup(tid, key)
    take_first(tid, :ets.next(tid, key), n - 1, [{player_id, score} | acc])
  end