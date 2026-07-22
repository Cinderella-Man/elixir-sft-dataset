  test "a locked path nested under an INTRODUCED subtree cannot be injected" do
    # The base defines nothing at all: the override's whole :db subtree is
    # introduced. The unlocked :host must arrive; the locked :password must
    # be stripped at depth — wholesale subtree copying would leak it.
    result =
      ConfigMerger.merge(%{}, %{db: %{password: "pwned", host: "h"}}, locked: [[:db, :password]])

    assert result == %{db: %{host: "h"}}
  end