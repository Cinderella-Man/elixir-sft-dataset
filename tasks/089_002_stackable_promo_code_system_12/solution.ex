  defp check_expired(%{valid_until: nil}, _now), do: :ok

  defp check_expired(%{valid_until: vu}, now) do
    if DateTime.compare(now, vu) == :gt, do: {:error, :expired}, else: :ok
  end