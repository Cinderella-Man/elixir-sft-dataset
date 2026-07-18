  @doc """
  Summarize the metrics file at `path`.

  Returns `{:ok, report}` on success, where `report` is a map with keys:

    :per_metric       – %{name_string => %{count, min, max, sum, mean}}
    :total_samples    – integer
    :time_range       – {first_dt, last_dt} | nil
    :samples_per_hour – %{{date_tuple, hour} => integer}
    :unique_tags      – %{tag_key => MapSet.t(tag_values)}
    :malformed_count  – integer

  Returns `{:error, reason}` if the file does not exist or cannot be opened
  (for example when `path` points at a directory).
  """
  @spec summarize(String.t()) :: {:ok, map()} | {:error, term()}
  def summarize(path) do
    with :ok <- ensure_readable(path) do
      report =
        path
        |> File.stream!(:line, [])
        |> Stream.map(&String.trim_trailing(&1, "\n"))
        |> Stream.map(&String.trim_trailing(&1, "\r"))
        |> Enum.reduce(initial_acc(), &process_line/2)
        |> build_report()

      {:ok, report}
    end
  rescue
    error in [File.Error] -> {:error, error.reason}
  end