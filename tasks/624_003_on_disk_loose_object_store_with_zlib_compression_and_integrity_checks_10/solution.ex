  @impl true
  @spec init(String.t()) :: {:ok, %{dir: String.t()}} | {:stop, term()}
  def init(dir) do
    case File.mkdir_p(dir) do
      :ok -> {:ok, %{dir: dir}}
      {:error, reason} -> {:stop, reason}
    end
  end