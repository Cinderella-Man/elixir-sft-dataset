  defp public_entry(entry) do
    Map.take(entry, [:id, :message, :error_reason, :metadata, :retry_count])
  end