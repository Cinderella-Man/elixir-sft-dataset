  test "params_for applies overrides" do
    params = Factory.params_for(:user, name: "Grace")
    assert params.name == "Grace"
  end