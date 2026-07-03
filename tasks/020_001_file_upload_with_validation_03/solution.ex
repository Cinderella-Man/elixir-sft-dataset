def validate(%Plug.Upload{filename: filename, path: path}) do
  case filename |> Path.extname() |> String.downcase() do
    ".csv" -> validate_csv(path)
    ".json" -> validate_json(path)
    _ -> {:error, "File type not allowed. Only .csv and .json files are accepted"}
  end
end