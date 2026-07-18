  def ingest(repo, schema, file_path, opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    on_conflict = Keyword.get(opts, :on_conflict, @default_on_conflict)
    conflict_target = Keyword.get(opts, :conflict_target, @default_conflict_target)
    field_mapping = Keyword.get(opts, :field_mapping, nil)

    with :ok <- check_file(file_path),
         {:ok, rows} <- parse_csv(file_path) do
      cfg = %{
        batch_size: batch_size,
        on_conflict: on_conflict,
        conflict_target: conflict_target
      }

      {:ok, process_rows(repo, schema, rows, field_mapping, cfg)}
    end
  end