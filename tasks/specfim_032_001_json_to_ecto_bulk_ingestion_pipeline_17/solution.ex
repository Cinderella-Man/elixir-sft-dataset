  @spec ingest(repo(), schema(), file_path(), ingest_opts()) ::
          {:ok, stats()}
          | {:error, :file_not_found | :invalid_json | :not_a_list | :conflict_target_required}