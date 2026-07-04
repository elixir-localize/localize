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
