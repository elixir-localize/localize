defmodule Localize.Calendar.ISO do
  @moduledoc false

  # A calendar answers what a format needs to know about its dates through
  # callbacks on its own module. `Calendar.ISO` has none of the Calendrical
  # behaviour's callbacks and Calendrical may not be present, so Localize
  # answers them for it here, as the Gregorian calendar:
  # `Localize.Calendar.answering/1` names this module for `Calendar.ISO`, and
  # every other calendar answers for itself. Every callback of the `Calendar`
  # behaviour is passed to `Calendar.ISO`, so every question Localize puts to
  # a calendar goes to the one module.

  for {name, arity} <- Calendar.behaviour_info(:callbacks) do
    arguments = Macro.generate_arguments(arity, __MODULE__)

    @doc false
    def unquote(name)(unquote_splicing(arguments)),
      do: Calendar.ISO.unquote(name)(unquote_splicing(arguments))
  end

  @doc false
  @spec cldr_calendar_type() :: :gregorian
  def cldr_calendar_type, do: :gregorian

  @doc false
  @spec era_calendar_type() :: :gregorian
  def era_calendar_type, do: :gregorian

  @doc false
  @spec month_of_year(Calendar.year(), Calendar.month(), Calendar.day()) :: Calendar.month()
  def month_of_year(_year, month, _day), do: month

  @doc false
  @spec cardinal_month(Calendar.month()) :: Calendar.month()
  def cardinal_month(month), do: month

  # The year as the calendar shows it: the proleptic year, which
  # `Localize.Calendar.displayed_year/1` counts back from the era below 1.
  @doc false
  @spec calendar_year(Calendar.year(), Calendar.month(), Calendar.day()) :: Calendar.year()
  def calendar_year(year, _month, _day), do: year

  @doc false
  @spec related_gregorian_year(Calendar.year(), Calendar.month(), Calendar.day()) ::
          Calendar.year()
  def related_gregorian_year(year, _month, _day), do: year

  # The Gregorian calendar has no cycle of years, so the year is its own
  # count of years, which CLDR names no cycle for.
  @doc false
  @spec cyclic_year(Calendar.year(), Calendar.month(), Calendar.day()) :: Calendar.year()
  def cyclic_year(year, _month, _day), do: year

  @doc false
  @spec iso_week_of_year(Calendar.year(), Calendar.month(), Calendar.day()) ::
          {Calendar.year(), pos_integer()}
  def iso_week_of_year(year, month, day), do: :calendar.iso_week_number({year, month, day})
end
