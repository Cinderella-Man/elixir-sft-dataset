  @spec level_for(non_neg_integer(), pos_integer(), pos_integer()) :: level()
  defp level_for(count, warn_after, crit_after) do
    cond do
      count >= crit_after -> :critical
      count >= warn_after -> :warning
      true -> :ok
    end
  end