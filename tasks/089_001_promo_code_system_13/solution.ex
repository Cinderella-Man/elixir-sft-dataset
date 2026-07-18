  defp check_expired(%{valid_until: nil}, _now), do: :ok

  defp check_expired(%{valid_until: valid_until}, now) do
    if DateTime.compare(now, valid_until) == :gt do
      {:error, :expired}
    else
      :ok
    end
  end