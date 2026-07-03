  defp reserve_and_persist(conn, upload, size, acct, store, upload_dir, base_url) do
    metadata = %{
      original_name: upload.filename,
      size: size,
      content_type: upload.content_type
    }

    case Store.save(store, acct, metadata) do
      {:ok, record, %{quota: quota, used: used}} ->
        ext = Path.extname(upload.filename)
        File.cp!(upload.path, Path.join(upload_dir, record.id <> ext))

        response = %{
          id: record.id,
          original_name: record.original_name,
          size: record.size,
          content_type: record.content_type,
          uploaded_at: record.uploaded_at,
          account_id: record.account,
          used_bytes: used,
          quota_bytes: quota,
          download_url: "#{base_url}/api/uploads/#{record.id}"
        }

        json(conn, 201, response)

      {:error, :quota_exceeded, %{quota: quota, used: used, requested: requested}} ->
        json(conn, 507, %{
          error: "Quota exceeded",
          quota_bytes: quota,
          used_bytes: used,
          requested_bytes: requested
        })
    end
  end