  @doc """
  Validates the persisted upload. Returns `:ok` when the file type is allowed
  and its contents pass the per-type checks, otherwise `{:error, reason}`.
  """
  @spec validate(Plug.Upload.t()) :: :ok | {:error, String.t()}
  def validate(%Plug.Upload{filename: filename, path: path}) do
    case filename |> Path.extname() |> String.downcase() do
      ".csv" -> validate_csv(path)
      ".json" -> validate_json(path)
      _ -> {:error, "File type not allowed. Only .csv and .json files are accepted"}
    end
  end