  defp serialize_item(item) do
    %{
      id: item.id,
      name: item.name,
      inserted_at: DateTime.to_iso8601(item.inserted_at)
    }
  end