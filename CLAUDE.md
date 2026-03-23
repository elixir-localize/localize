## Error returns from public API functions

Our objective is to return error tuples that can both machine readable and can also produce localized human-readable messages.

* The standard non-error return is {:ok, return_value}

* An error return is {:error, MyAppError.exception(bindings)}

* bindings is a keyword list representing the data that will be used to form the exception message

## Exceptions

* Exceptions are stored in the lib/localize/exception directoy

* One exception is defined in one file

### Exception definition

An exception is defined as follows

```elixir
defmodule MyAppError do
  defexception [binding names]

  @impl true
  def exception(bindings) do
    %MyAppError{bindings}
  end
  
  @impl true
  def message(exception struct) do
    Gettext.dpgettext(Localize.Gettext, domain, msgctxt, msgid, bindings)  
  end
end
````

In the example above:

* domain - is always "localize"
* msgctxt - is a string representing which module of Localize we are working on. The main modules are "language_tag", "locale", "number", "datetime", "currency", "unit"
* msgid is the message string in Unicode Message Format 2 format with interpolation of the struct bindings
* bindings - the bindings derived from the struct

## Locale parsing

* When we need to parse or resolve a locale identifier, prefer `Localize.validate_locale/1` over `Localize.LanguageTag.parse/1`. Validation canonicalizes the tag, populates the `LanguageTag.U` struct for `-u-` extensions, resolves likely subtags, and caches the result.

## When adapting code from ex_cldr and related libraries

ex_cldr standard error returns are of the for {:error, {exception, message}}. When adapting a function from ex_cldr to operating in Localize, the following should done:

* Map the exception name into the localize domain by removing the Cldr prefix and replacing it with Localize

* Create an expcetion file including a defexception according to our local rules

* Attempt to identify relevant bindings for the message and re-write the message in MF2 format

* Update the :error tuple to be of the standard format described about

* Keep a track of the functions not adapted and merged in the TODO.md file so we can come back to it later

