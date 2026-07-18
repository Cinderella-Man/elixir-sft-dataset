  defp sanitize_field(:text, v) when is_binary(v), do: {:ok, escape_text(v)}
  defp sanitize_field(:text, _), do: {:error, :not_a_string}

  defp sanitize_field(:identifier, v) when is_binary(v), do: sql_identifier(v)
  defp sanitize_field(:identifier, _), do: {:error, :not_a_string}

  defp sanitize_field(:filename, v) when is_binary(v), do: filename(v)
  defp sanitize_field(:filename, _), do: {:error, :not_a_string}

  defp sanitize_field(:integer, v) when is_integer(v), do: {:ok, v}

  defp sanitize_field(:integer, v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {n, ""} -> {:ok, n}
      _ -> {:error, :not_an_integer}
    end
  end

  defp sanitize_field(:integer, _), do: {:error, :not_an_integer}

  defp sanitize_field(:boolean, v) when is_boolean(v), do: {:ok, v}
  defp sanitize_field(:boolean, "true"), do: {:ok, true}
  defp sanitize_field(:boolean, "false"), do: {:ok, false}
  defp sanitize_field(:boolean, _), do: {:error, :not_a_boolean}

  defp sanitize_field(type, _), do: {:error, {:unknown_field_type, type}}