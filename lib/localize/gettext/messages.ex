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

      # Language tag
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "language_tag",
        "Could not parse {$input}: {$reason}"
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
        "No parent territory found for {$territory}."
      ),
      Gettext.Macros.dpgettext_noop_with_backend(
        Localize.Gettext,
        "localize",
        "locale",
        "The cached locale {$locale_id} has version {$cached_version} but the current version is {$current_version}."
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
        "The measurement system {$measurement_system} is not known."
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
      )
    ]
  end
end
