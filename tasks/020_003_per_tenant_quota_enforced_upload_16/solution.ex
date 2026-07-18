  defp account(conn) do
    case get_req_header(conn, "x-account-id") do
      [a | _] when is_binary(a) and a != "" -> a
      _ -> nil
    end
  end