  defp find_busy_worker(busy_workers, target_ref) do
    Enum.find(busy_workers, fn {_pid, {ref, _client}} -> ref == target_ref end)
  end