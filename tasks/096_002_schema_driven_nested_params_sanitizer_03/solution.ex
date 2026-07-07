  @doc "Safe filename (`{:ok, s}` or `{:error, :empty}`)."
  @spec filename(String.t()) :: {:ok, String.t()} | {:error, :empty}
  def filename(input) when is_binary(input) do
    sanitized =
      input
      |> String.replace("\0", "")
      |> String.replace("/", "")
      |> String.replace("\\", "")
      |> String.replace(~r/[^a-zA-Z0-9_\-.]/, "")
      |> String.replace(~r/\.{2,}/, ".")
      |> String.trim(".")

    if sanitized == "" do
      {:error, :empty}
    else
      {:ok, sanitized}
    end
  end