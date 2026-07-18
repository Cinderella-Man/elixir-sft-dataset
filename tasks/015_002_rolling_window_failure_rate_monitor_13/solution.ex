  # If pending and we just got an :ok, move to :up. Otherwise keep current.
  defp maybe_upgrade_pending(:pending, :ok), do: :up
  defp maybe_upgrade_pending(current, _), do: current