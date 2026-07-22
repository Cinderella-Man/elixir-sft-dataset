defp store_and_persist(conn, upload, size, store, upload_dir, base_url) do
  metadata = %{
    original_name: upload.filename,
    size: size,
    content_type: upload.content_type
  }

  {:ok, record} = Store.save(store, metadata)

  ext = Path.extname(upload.filename)
  dest = Path.join(upload_dir, record.id <> ext)
  File.cp!(upload.path, dest)

  download_url = "#{base_url}/api/uploads/#{record.id}"
  response = Map.put(record, :download_url, download_url)

  json(conn, 201, response)
end