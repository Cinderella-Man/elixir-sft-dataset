  defp check_not_yet_valid(%{valid_from: nil}, _now), do: :ok

  defp check_not_yet_valid(%{valid_from: valid_from}, now) do
    if DateTime.compare(now, valid_from) == :lt do
      {:error, :not_yet_valid}
    else
      :ok
    end
  end