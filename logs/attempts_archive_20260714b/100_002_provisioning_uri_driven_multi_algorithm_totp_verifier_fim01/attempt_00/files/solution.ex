  defp parse_label(path) when is_binary(path) do
    label =
      path
      |> String.replace_prefix("/", "")
      |> URI.decode()

    case String.split(label, ":", parts: 2) do
      [""] ->
        {:error, :missing_label}

      [account] ->
        {:ok, nil, account}

      [issuer, account] ->
        issuer = String.trim(issuer)
        account = strip_leading_space(account)

        if issuer == "" or account == "" do
          {:error, :missing_label}
        else
          {:ok, issuer, account}
        end
    end
  end

  defp parse_label(_path), do: {:error, :missing_label}