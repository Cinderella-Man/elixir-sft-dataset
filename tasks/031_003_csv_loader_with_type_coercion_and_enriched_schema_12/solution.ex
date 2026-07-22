  @doc """
  Loads CSV at `file_path`, coercing rows to `schema`.

  Returns `{:ok, valid_rows, error_report}` (the same 3-tuple `load_string/2`
  documents) or `{:error, :file_not_found | :empty_file}`.
  """
  @spec load_file(String.t(), [map()]) ::
          {:ok, [map()], [{pos_integer(), String.t(), String.t()}]}
          | {:error, :file_not_found | :empty_file}
  def load_file(file_path, schema) do
    case File.read(file_path) do
      {:ok, ""} ->
        {:error, :empty_file}

      {:ok, contents} ->
        load_string(contents, schema)

      {:error, :enoent} ->
        {:error, :file_not_found}
    end
  end