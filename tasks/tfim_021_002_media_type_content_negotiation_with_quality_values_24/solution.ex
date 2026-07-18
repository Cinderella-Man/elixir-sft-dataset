  test "plug honours custom :supported and :default options" do
    opts = MediaVersionApi.Plugs.AcceptVersion.init(supported: ["v1"], default: "v1")

    absent = MediaVersionApi.Plugs.AcceptVersion.call(conn(:get, "/api/users/1"), opts)
    refute absent.halted
    assert absent.assigns[:api_version] == "v1"

    wildcard =
      conn(:get, "/api/users/1")
      |> Plug.Conn.put_req_header("accept", "*/*")
      |> MediaVersionApi.Plugs.AcceptVersion.call(opts)

    assert wildcard.assigns[:api_version] == "v1"

    rejected =
      conn(:get, "/api/users/1")
      |> Plug.Conn.put_req_header("accept", "application/vnd.acme.v2+json")
      |> MediaVersionApi.Plugs.AcceptVersion.call(opts)

    assert rejected.halted
    assert rejected.status == 406
    assert Jason.decode!(rejected.resp_body)["supported"] == ["v1"]
  end