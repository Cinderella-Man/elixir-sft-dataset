  @doc """
  Ingests records from a JSON array file into the database.

  ## Parameters

    - `repo`      – An Ecto repository module (e.g. `MyApp.Repo`).
    - `schema`    – An Ecto schema module whose table will receive the rows.
    - `file_path` – Absolute or relative path to a UTF-8 JSON file whose
                    top-level value is an array of objects.
    - `opts`      – Keyword list; see module doc for accepted keys.

  ## Return values

    - `{:ok, stats}` – Always returned when the file was read and parsed
                       successfully, even if individual batches failed.
    - `{:error, :file_not_found}` – The file does not exist or is unreadable.
    - `{:error, :invalid_json}`   – The file contents are not valid JSON.
    - `{:error, :not_a_list}`     – The JSON root value is not an array.
    - `{:error, :conflict_target_required}` – `on_conflict` is the default
      `:replace_all` but no `:conflict_target` was given (Ecto requires the
      conflict columns to build an upsert).
  """
  @spec ingest(repo(), schema(), file_path(), ingest_opts()) ::
          {:ok, stats()}
          | {:error, :file_not_found | :invalid_json | :not_a_list | :conflict_target_required}
  def ingest(repo, schema, file_path, opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    on_conflict = Keyword.get(opts, :on_conflict, @default_on_conflict)
    conflict_target = Keyword.get(opts, :conflict_target, @default_conflict_target)
    returning = Keyword.get(opts, :returning, @default_returning)

    with {:ok, raw} <- read_file(file_path),
         {:ok, parsed} <- parse_json(raw),
         {:ok, records} <- validate_list(parsed),
         :ok <- validate_conflict_opts(records, on_conflict, conflict_target) do
      cfg = %{
        batch_size: batch_size,
        on_conflict: on_conflict,
        conflict_target: conflict_target,
        returning: returning
      }

      {:ok, process_batches(repo, schema, records, cfg)}
    end
  end