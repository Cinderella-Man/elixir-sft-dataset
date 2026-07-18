  defp handle_upload(conn, upload, opts) do
    store = Keyword.fetch!(opts, :store)
    upload_dir = Keyword.fetch!(opts, :upload_dir)
    base_url = Keyword.fetch!(opts, :base_url)

    case Validator.validate(upload) do
      :ok ->
        size = File.stat!(upload.path).size
        store_and_persist(conn, upload, size, store, upload_dir, base_url)

      {:error, reason} ->
        json(conn, 422, %{error: reason})
    end
  end