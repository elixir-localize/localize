defmodule Localize.Gettext.Messages do
  @moduledoc false

  # This module exists solely for Gettext message extraction.
  #
  # Exception modules use `Gettext.dpgettext/5` (the runtime function)
  # rather than the Gettext backend macros because the exception modules
  # compile before the Gettext backend is available. The runtime function
  # works correctly but is invisible to `mix gettext.extract`.
  #
  # By declaring all exception message strings here with
  # `dpgettext_noop_with_backend`, we make them visible to the extractor
  # so they appear in the `.pot` files for translation.

  require Gettext.Macros

  def __messages__ do
    [
      # Currency
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "currency",
        "The currency {$currency} has no display name in locale {$locale}."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "currency",
        "The currency {$currency} has no localized data in locale {$locale}."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "currency",
        "The currency {$currency} is not known."
      ),

      # DateTime
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "datetime",
        "Could not tokenize the format {$format}: {$detail}."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "datetime",
        "Date must have at least one of :year, :month, or :day keys."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "datetime",
        "Datetime must have date and/or time keys."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "datetime",
        "Invalid interval format {$detail}."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "datetime",
        "No available format resolved for {$format} in locale {$locale}."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "datetime",
        "No interval format found for {$format_key}."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "datetime",
        "No interval pattern for difference {$detail} in format {$format_key}."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "datetime",
        "The format {$format} is invalid."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "datetime",
        "The format {$format} is invalid: {$reason}."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "datetime",
        "Time must have at least one of :hour, :minute, or :second keys."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "datetime",
        "Unknown interval style {$style} or format {$format}."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "datetime",
        "Unterminated quote in interval format."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "datetime",
        "No interval format fallback pattern available in the locale data."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "datetime",
        "Interval endpoints must be the same kind of value. Found {$detail}."
      ),

      # Language tag
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "language_tag",
        "Could not parse {$input}: {$reason}"
      ),

      # MF2 message parse error with line/column
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "message",
        "Could not parse {$input} at line {$line} column {$column}: {$reason}"
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "language_tag",
        "No likely subtags data found for {$locale}"
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "language_tag",
        "No matching locale found for {$desired} within distance {$threshold}"
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "language_tag",
        "No unicode script {$value} found."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "language_tag",
        "The date {$value} must be the last value in subtag {$key}."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "language_tag",
        "The key {$key} is not valid for the -u- subtag."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "language_tag",
        "The value {$value} is not valid for the key {$key}."
      ),

      # Locale
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "locale",
        "No locale display data for {$locale}."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "locale",
        "The locale {$locale_id} downloaded from {$url} has no entry in the locale hash manifest."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "locale",
        "The locale {$locale_id} downloaded from {$url} failed integrity verification. Expected SHA-256 {$expected} but the content hashes to {$actual}."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "locale",
        "No parent territory found for {$territory}."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "locale",
        "The cached locale {$locale_id} has CLDR data version {$cached_version} but this release of Localize requires {$current_version}. Run `mix localize.download_locales {$locale_id_bare}` to refresh it, or set `config :localize, :allow_runtime_locale_download, true` to enable on-demand downloading."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "locale",
        "The calendar {$calendar} is not known."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "locale",
        "The key path {$keys} was not found in locale {$locale}."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "locale",
        "The language {$language} is not known."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "locale",
        "The locale {$locale_id} could not be downloaded from {$url}: {$reason}."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "locale",
        "The locale {$locale_id} could not be written to the cache at {$path}: {$reason}."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "locale",
        "The locale {$locale_id} is not known."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "locale",
        "The locale {$locale_id} is not valid."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "locale",
        "The locale {$locale_id} was not found in the cache at {$path}. Run `mix localize.download_locales {$locale_id_bare}` to download it, or set `config :localize, :allow_runtime_locale_download, true` to enable on-demand downloading."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "locale",
        "The locale {$locale} has no parent locale"
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "locale",
        "The script {$script} is not known."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "locale",
        "The subdivision {$subdivision} is not known."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "locale",
        "The territory {$territory} is not known."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "locale",
        "Unknown timezone: {$timezone}"
      ),

      # Message
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "message",
        "Cannot format {$value} with function {$function}"
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "message",
        "Cannot format {$value} with function {$function}: {$reason}"
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "message",
        "No binding was found for {$unbound}"
      ),

      # Number
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "number",
        "The number system {$number_system} is not known."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "number",
        "The number system {$number_system} is not valid for locale {$locale}."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "number",
        "The measurement system {$measurement_system} is not known."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "number",
        "The RBNF rule {$rule_name} is not known for locale {$locale}."
      ),

      # Plural rules
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "plural_rules",
        "No{$type} plural rules available for the locale {$locale_id}."
      ),

      # Unit
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "unit",
        "Cannot apply {$operation} to a unit without a value."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "unit",
        "Cannot compute conversion factor for mixed units."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "unit",
        "Cannot convert from {$from} to {$to}."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "unit",
        "Expected {$expected} for {$context}, got: {$value}"
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "unit",
        "Expected {$expected}, got: {$value}"
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "unit",
        "No quantity found for base unit {$unit}."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "unit",
        "No unit preference for region {$region} in category {$category}."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "unit",
        "No unit preferences for category {$category} and usage {$usage}."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "unit",
        "No unit preferences found for quantity {$quantity}."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "unit",
        "Special conversion is not supported for {$from}."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "unit",
        "Units {$from} and {$to} are not convertible."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "unit",
        "Unknown unit: {$unit}"
      ),

      # Style
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "unknown style error",
        "The style {$style} is unknown."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "unknown style error",
        "The style {$style} is unknown for territory {$territory}."
      ),

      # FormatError — structural reason atoms
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "message",
        "Cannot format {$value}: unbalanced markup: unclosed markup tag"
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "message",
        "Cannot format {$value}: unbalanced markup: {$detail}"
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "message",
        "Cannot format {$value}: unbalanced markup: close tag {$detail} does not match open"
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "message",
        "Cannot format {$value} with function {$function}: {$detail}"
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "message",
        "Invalid message: the variable {$detail} is declared more than once"
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "message",
        "Invalid message: the option {$detail} appears more than once in the same expression"
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "message",
        "Invalid message: more than one variant has the keys {$detail}"
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "message",
        "Cannot format message: unknown function {$detail}"
      ),

      # ParseError — structural reason atoms
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "message",
        "Could not parse {$input} at line {$line} column {$column}: unexpected trailing input {$rest}"
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "message",
        "Could not parse {$input} at position {$position}: unexpected trailing input {$rest}"
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "message",
        "Could not parse {$input}: unexpected trailing input {$rest}"
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "message",
        "Could not parse {$input} at line {$line} column {$column}: {$detail}{$tail}"
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "message",
        "Could not parse {$input} at position {$position}: {$detail}{$tail}"
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "message",
        "Could not parse {$input}: {$detail}{$tail}"
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "message",
        "Could not parse {$input}: input ended unexpectedly"
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "message",
        "Could not parse {$input}: {$detail}"
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "message",
        "Could not parse {$input}"
      ),

      # LocaleDownloadError — structural reason atoms
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "locale",
        "The locale {$locale_id} at {$url} is unchanged since the last download."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "locale",
        "The locale {$locale_id} could not be downloaded from {$url}: HTTP {$status}."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "locale",
        "The locale {$locale_id} could not be downloaded from {$url}: connection timed out."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "locale",
        "The locale {$locale_id} could not be downloaded from {$url}: request timed out."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "locale",
        "The locale {$locale_id} could not be downloaded from {$url}: host could not be resolved."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "locale",
        "The locale {$locale_id} was downloaded from {$url} but failed safe decoding."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "locale",
        "The locale {$locale_id} downloaded from {$url} does not match the expected version."
      ),

      # LocaleCacheWriteError — structural reason atoms
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "locale",
        "Cannot write locale {$locale_id} to {$path}: permission denied."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "locale",
        "Cannot write locale {$locale_id} to {$path}: parent directory does not exist."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "locale",
        "Cannot write locale {$locale_id} to {$path}: no space left on device."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "locale",
        "Cannot write locale {$locale_id} to {$path}: filesystem is read-only."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "locale",
        "Cannot write locale {$locale_id} to {$path}: file already exists."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "locale",
        "Cannot write locale {$locale_id} to {$path}: {$reason}."
      ),

      # LocaleNotFoundInCacheError — read-error variant
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "locale",
        "The locale {$locale_id} could not be read from the cache at {$path}: {$reason}."
      ),

      # InvalidValueError — atom :expected + :allowed_values
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "unit",
        "Expected a valid {$expected}{$context_part}, got: {$value} (allowed values: {$allowed})"
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "unit",
        "Expected a valid {$expected}{$context_part}, got: {$value}"
      ),

      # NoCertificateStoreError
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "locale",
        "No certificate trust store was found. Tried looking for: {$searched}. Install the `castore` or `certifi` hex package, or configure `config :localize, cacertfile: \"/path/to/cacertfile\"`."
      )
    ]
  end
end
