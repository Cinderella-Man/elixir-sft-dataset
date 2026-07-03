  def call(conn, opts) do
    default = Keyword.get(opts, :default, "v2")

    version =
      case get_req_header(conn, "accept-version") do
        [v | _] -> v
        [] -> default
      end

    case Map.get(@statuses, version) do
      nil ->
        halt_json(conn, 406, %{error: "unsupported version", supported: requestable()})

      :retired ->
        halt_json(conn, 410, %{
          error: "version retired",
          version: version,
          supported: requestable()
        })

      :deprecated ->
        conn
        |> assign(:api_version, version)
        |> put_deprecation_headers(version)

      :active ->
        assign(conn, :api_version, version)
    end
  end