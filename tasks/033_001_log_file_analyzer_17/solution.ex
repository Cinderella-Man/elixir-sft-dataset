  @doc """
  Analyze the log file at `path`.

  Returns `{:ok, report}` on success, where `report` is a map with keys:

    :counts_by_level  – %{level_string => integer}
    :error_rate       – float in [0.0, 1.0]
    :top_errors       – [{message, count}] (up to 10, desc by count)
    :time_range       – {first_dt, last_dt} | nil
    :errors_per_hour  – %{{date_tuple, hour} => integer}
    :malformed_count  – integer

  Returns `{:error, reason}` if the file does not exist or cannot be opened
  (for example when `path` points at a directory).
  """
  @spec analyze(String.t()) :: {:ok, map()} | {:error, term()}
  def analyze(path) do
    # File.stream!/3 is lazy and raises on the first pull, so we probe the path
    # eagerly with File.open/2. This catches missing files as well as paths that
    # exist but cannot be read (directories, permission errors, ...).
    case File.open(path, [:read]) do
      {:error, reason} ->
        {:error, reason}

      {:ok, io_device} ->
        File.close(io_device)
        stream_report(path)
    end
  end