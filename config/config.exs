import Config

# Localize is a library: this configuration applies only to this
# project's own dev/test environments and is not consulted by
# consumers of the hex package.
#
# `:domain` is declared so that the `domain: :localize` metadata
# attached to Localize's log messages is rendered in dev/test output
# (and so Credo's MissedMetadataKeyInLoggerConfig check reflects
# reality).
config :logger, :default_formatter, metadata: [:domain]

# CLDR's datetime conformance fixtures format in real timezones
# (`Australia/Adelaide`), which needs a timezone database to resolve the
# offset and the daylight flag. `:tz` is an optional dependency, installed
# for this project but not imposed on consumers: parsing an ISO 8601 offset
# needs no database, and a consumer who wants named zones resolved brings
# their own (`:tz` or `:tzdata`) and configures it themselves.
if config_env() == :test do
  config :elixir, :time_zone_database, Tz.TimeZoneDatabase
end
