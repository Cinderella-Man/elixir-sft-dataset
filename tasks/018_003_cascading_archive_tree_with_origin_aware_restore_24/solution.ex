  defp check_archived(node) do
    if live?(node), do: {:error, :not_archived}, else: :ok
  end