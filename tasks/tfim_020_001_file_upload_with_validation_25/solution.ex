  test "Validator.validate/1 is callable directly with a %Plug.Upload{} struct", _ctx do
    csv_path = Path.join(@upload_dir, "direct_validator_ok.csv")
    File.write!(csv_path, "name,email\nAlice,a@example.com\n")

    csv_upload = %Plug.Upload{
      path: csv_path,
      filename: "direct_validator_ok.csv",
      content_type: "text/csv"
    }

    assert FileUpload.Validator.validate(csv_upload) == :ok

    txt_path = Path.join(@upload_dir, "direct_validator_bad.txt")
    File.write!(txt_path, "plain text")

    txt_upload = %Plug.Upload{
      path: txt_path,
      filename: "direct_validator_bad.txt",
      content_type: "text/plain"
    }

    assert {:error, reason} = FileUpload.Validator.validate(txt_upload)
    assert is_binary(reason)
  end