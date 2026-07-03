  defp status_body(record) do
    base = %{
      id: record.id,
      original_name: record.original_name,
      size: record.size,
      content_type: record.content_type,
      uploaded_at: record.uploaded_at,
      status: Atom.to_string(record.status)
    }

    case record.status do
      :valid -> Map.put(base, :download_url, Map.get(record, :download_url))
      :invalid -> Map.put(base, :error, Map.get(record, :error))
      _ -> base
    end
  end