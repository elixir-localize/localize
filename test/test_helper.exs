Application.put_env(:localize, :default_locale, :en)
# Integration tests (slow — spawn mix subprocesses, compile deps) are
# excluded by default. Run them with `mix test --include integration`.
ExUnit.start(exclude: [:integration])
