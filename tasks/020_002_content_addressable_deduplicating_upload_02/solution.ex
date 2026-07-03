defp store_and_persist(conn, upload, size, store, upload_dir, base_url) do
  content = File.read!(upload.path)
  hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

  metadata = %{
    original_name: upload.filename,
    size: size,
    content_type: upload.content_type
  }

  {status_code, dedup?, record} =
    case Store.save(store, hash, metadata) do
      {:ok, :created, record} ->
        ext = Path.extname(upload.filename)
        File.cp!(upload.path, Path.join(upload_dir, hash <> ext))
        {201, false, record}

      {:ok, :exists, record} ->
        {200, true, record}
    end

  response = %{
    id: record.id,
    original_name: record.original_name,
    size: record.size,
    content_type: record.content_type,
    uploaded_at: record.uploaded_at,
    upload_count: record.upload_count,
    deduplicated: dedup?,
    download_url: "#{base_url}/api/uploads/#{record.id}"
  }

  json(conn, status_code, response)
end