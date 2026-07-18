  @impl true
  def init(opts) do
    max_len = Keyword.get(opts, :max_filename_length, 255)
    {:ok, %{max_filename_length: max_len, metrics: @default_metrics}}
  end