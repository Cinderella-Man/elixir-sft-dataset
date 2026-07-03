  defp accept_upload(conn, upload, opts) do
    store = Keyword.fetch!(opts, :store)
    upload_dir = Keyword.fetch!(opts, :upload_dir)
    base_url = Keyword.fetch!(opts, :base_url)

    size = File.stat!(upload.path).size

    cond do
      size > @max_bytes ->
        json(conn, 413, %{error: "File too large", max_bytes: @max_bytes})

      true ->
        metadata = %{
          original_name: upload.filename,
          size: size,
          content_type: upload.content_type
        }

        {:ok, record} = Store.create(store, metadata)

        ext = Path.extname(upload.filename)
        dest = Path.join(upload_dir, record.id <> ext)
        File.cp!(upload.path, dest)

        spawn_validation(store, record, dest, base_url)

        response = %{
          id: record.id,
          original_name: record.original_name,
          size: record.size,
          content_type: record.content_type,
          status: "pending",
          uploaded_at: record.uploaded_at,
          status_url: "#{base_url}/api/uploads/#{record.id}"
        }

        json(conn, 202, response)
    end
  end