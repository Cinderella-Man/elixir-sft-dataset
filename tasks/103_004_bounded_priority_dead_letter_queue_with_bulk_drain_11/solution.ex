  defp public(e) do
    Map.take(e, [:id, :message, :error_reason, :metadata, :priority, :retry_count])
  end