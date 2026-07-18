  def ingest(repo, schema, file_path, opts \\ []) do
    if File.exists?(file_path) do
      cfg = %{
        batch_size: Keyword.get(opts, :batch_size, @default_batch_size),
        on_conflict: Keyword.get(opts, :on_conflict, @default_on_conflict),
        conflict_target: Keyword.get(opts, :conflict_target, @default_conflict_target),
        max_concurrency: Keyword.get(opts, :max_concurrency, @default_max_concurrency),
        timeout: Keyword.get(opts, :timeout, @default_timeout)
      }

      {:ok, stream_and_process(repo, schema, file_path, cfg)}
    else
      Logger.error("[JsonlIngestion] File not found: #{inspect(file_path)}")
      {:error, :file_not_found}
    end
  end