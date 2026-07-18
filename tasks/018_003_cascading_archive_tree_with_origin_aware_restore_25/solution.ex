  defp check_direct(node) do
    if node.archive_origin == :cascade, do: {:error, :cascade_archived}, else: :ok
  end