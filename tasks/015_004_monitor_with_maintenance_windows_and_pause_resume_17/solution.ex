  # Compute the reported status from the internal health + mode.
  @spec reported_status(service()) :: status()
  defp reported_status(%{mode: :paused}), do: :paused
  defp reported_status(%{mode: :maintenance}), do: :maintenance
  defp reported_status(%{health: health}), do: health