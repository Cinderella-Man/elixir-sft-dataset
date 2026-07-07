  test "mixed errors and warnings keep canonical ordering" do
    report = PasswordPolicy.audit("abc", %{username: "operator"})
    assert report.errors == [:too_short]
    assert report.warnings == [:no_uppercase, :no_digit, :no_special]

    strict = PasswordPolicy.audit("abc", %{username: "operator", strict: true})
    assert strict.errors == [:too_short, :no_uppercase, :no_digit, :no_special]
    assert strict.warnings == []
  end