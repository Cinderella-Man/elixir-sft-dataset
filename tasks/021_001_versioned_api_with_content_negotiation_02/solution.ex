def call(conn, opts) do
  supported = Keyword.get(opts, :supported, ["v1", "v2"])
  default = Keyword.get(opts, :default, "v2")

  version =
    case get_req_header(conn, "accept-version") do
      [v | _] -> v
      [] -> default
    end

  if version in supported do
    assign(conn, :api_version, version)
  else
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(406, Jason.encode!(%{error: "unsupported version", supported: supported}))
    |> halt()
  end
end