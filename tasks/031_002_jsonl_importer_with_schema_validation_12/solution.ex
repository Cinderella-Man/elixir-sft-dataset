  @doc """
  Import a JSONL file at `file_path`, validate every record against `schema`.

  Returns:
    - `{:ok, valid_records, error_report}` on success
    - `{:error, :file_not_found}` if the file does not exist
    - `{:error, :empty_file}` if the file is zero bytes or contains no non-blank lines
  """
  @spec import_file(String.t(), [map()]) ::
          {:ok, [map()], [{pos_integer(), String.t(), String.t()}]}
          | {:error, :file_not_found | :empty_file}
  def import_file(file_path, schema) do
    case File.read(file_path) do
      {:ok, ""} ->
        {:error, :empty_file}

      {:ok, contents} ->
        import_string(contents, schema)

      {:error, :enoent} ->
        {:error, :file_not_found}
    end
  end