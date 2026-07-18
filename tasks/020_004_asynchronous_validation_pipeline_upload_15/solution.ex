  defp spawn_validation(store, record, dest, base_url) do
    Task.start(fn ->
      persisted = %Plug.Upload{
        filename: record.original_name,
        path: dest,
        content_type: record.content_type
      }

      case Validator.validate(persisted) do
        :ok ->
          Store.update_status(store, record.id, :valid, %{
            download_url: "#{base_url}/api/uploads/#{record.id}/download"
          })

        {:error, reason} ->
          Store.update_status(store, record.id, :invalid, %{error: reason})
      end
    end)
  end