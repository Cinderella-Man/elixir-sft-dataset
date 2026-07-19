  @spec next_run(server(), job_name()) ::
          {:ok, NaiveDateTime.t()} | {:error, :not_found}