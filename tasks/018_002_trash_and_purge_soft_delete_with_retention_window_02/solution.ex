  defp status(%{deleted_at: nil}, _now, _retention), do: :active

  defp status(%{deleted_at: da}, now, retention) do
    if now - da >= retention, do: :expired, else: :trashed
  end