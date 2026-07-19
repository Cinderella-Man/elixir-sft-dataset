  @spec process(Path.t(), (term() -> term()), keyword()) ::
          {:ok, stats()} | {:error, :too_many_errors, stats()}