  def decode_line(line) do
    trimmed = String.trim(line)

    case JSON.decode(trimmed) do
      {:ok, value} -> {:ok, value}
      {:error, _reason} -> {:error, {:invalid_json, trimmed}}
    end
  end