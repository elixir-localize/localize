defmodule Localize.Territory.HemisphereTest do
  @moduledoc """
  Covers `Localize.Territory.Hemisphere`.

  The classification is the library's own — CLDR carries no latitude for a
  territory — so the bulk of this file checks it against the IANA time zone
  database, which records a latitude for the zone each territory owns.

  """

  use ExUnit.Case, async: true

  alias Localize.Territory.Hemisphere

  doctest Localize.Territory.Hemisphere

  describe "hemisphere/1" do
    test "a territory below the equator is southern" do
      for territory <- [:AU, :NZ, :AR, :ZA, :CL, :FJ, :MG, :TL, :AQ] do
        assert {:ok, :southern} = Hemisphere.hemisphere(territory),
               "expected #{inspect(territory)} to be southern"
      end
    end

    test "a territory above the equator is northern" do
      for territory <- [:JP, :FR, :US, :CA, :IN, :EG, :MX, :NO, :PH] do
        assert {:ok, :northern} = Hemisphere.hemisphere(territory),
               "expected #{inspect(territory)} to be northern"
      end
    end

    test "a territory the equator runs through is ambiguous" do
      for territory <- [:BR, :CD, :CG, :CO, :EC, :GA, :ID, :KE, :KI, :MV, :SO, :ST, :UG] do
        assert {:ok, :ambiguous} = Hemisphere.hemisphere(territory),
               "expected #{inspect(territory)} to be ambiguous"
      end
    end

    test "a territory code may be a string" do
      assert {:ok, :southern} = Hemisphere.hemisphere("AU")
      assert {:ok, :northern} = Hemisphere.hemisphere("jp")
    end

    test "a locale is answered by its effective territory" do
      for {locale, expected} <- [
            {"en-AU", :southern},
            {"mi-NZ", :southern},
            {"pt-BR", :ambiguous},
            {"sw-KE", :ambiguous},
            {"fr-FR", :northern},
            {"ja", :northern}
          ] do
        {:ok, language_tag} = Localize.validate_locale(locale)

        assert {:ok, ^expected} = Hemisphere.hemisphere(language_tag),
               "expected #{locale} to be #{expected}"
      end
    end

    test "a locale with no territory of its own takes the one likely subtags give it" do
      {:ok, language_tag} = Localize.validate_locale("mi")
      assert {:ok, :NZ} = Localize.Territory.territory_from_locale(language_tag)
      assert {:ok, :southern} = Hemisphere.hemisphere(language_tag)
    end

    test "a region takes the hemisphere its territories agree on" do
      assert {:ok, :southern} = Hemisphere.hemisphere(:"053")
      assert {:ok, :southern} = Hemisphere.hemisphere(:"054")
      assert {:ok, :southern} = Hemisphere.hemisphere(:"061")
      assert {:ok, :northern} = Hemisphere.hemisphere(:"150")
      assert {:ok, :northern} = Hemisphere.hemisphere(:"154")
    end

    test "a region holding territories either side of the equator is ambiguous" do
      for region <- ~w(001 002 005 009 019 142 419) do
        assert {:ok, :ambiguous} = Hemisphere.hemisphere(String.to_atom(region)),
               "expected region #{region} to be ambiguous"
      end
    end

    test "a code shaped like a territory but naming none is refused" do
      for code <- [:QQ, :XX, :ZZ] do
        assert {:error, %Localize.UnknownTerritoryError{}} = Hemisphere.hemisphere(code),
               "expected #{inspect(code)} to be refused"
      end
    end

    test "every territory CLDR knows is answered" do
      for territory <- Localize.Territory.known_territories() do
        assert {:ok, hemisphere} = Hemisphere.hemisphere(territory),
               "no hemisphere for #{inspect(territory)}"

        assert hemisphere in [:northern, :southern, :ambiguous]
      end
    end
  end

  describe "hemisphere!/1" do
    test "returns the hemisphere" do
      assert Hemisphere.hemisphere!(:NZ) == :southern
    end

    test "raises for a code naming no territory" do
      assert_raise Localize.UnknownTerritoryError, fn -> Hemisphere.hemisphere!(:QQ) end
    end
  end

  describe "against the IANA time zone database" do
    # `zone1970.tab` records, for each zone, the coordinates of the place the
    # zone is named for and the territories that keep its time. The first
    # code on a line is the territory that place is in; the rest merely keep
    # that zone's time, which is why Antarctica is listed beside Riyadh. So
    # only the first code tells us where a territory is, and the 107 codes
    # that never appear first own no coordinate to check.
    @equator_crossing [:BR, :CD, :CG, :CO, :EC, :GA, :ID, :KE, :KI, :MV, :SO, :ST, :UG, :UM]

    test "every territory owning a zone agrees with its latitude" do
      case iana_latitudes() do
        :no_data ->
          # The table ships with the `tz` dependency; without it there is
          # nothing to check against, and the rest of the file still runs.
          assert true

        latitudes ->
          assert map_size(latitudes) > 100,
                 "expected the IANA table to cover a hundred territories or more"

          disagreements =
            for {territory, latitude} <- latitudes,
                territory not in @equator_crossing,
                {:ok, hemisphere} = Hemisphere.hemisphere(territory),
                expected = if(latitude < 0, do: :southern, else: :northern),
                hemisphere != expected do
              {territory, hemisphere, expected, latitude}
            end

          assert disagreements == [],
                 "these disagree with the latitude IANA records:\n" <>
                   Enum.map_join(disagreements, "\n", fn {t, got, want, lat} ->
                     "  #{inspect(t)}: #{got}, but its zone is at #{lat} (#{want})"
                   end)
      end
    end

    # The latitude of the zone each territory owns, in degrees, positive for
    # north. A territory owning several takes the first; they agree in sign
    # except for the equator-crossing territories left out above.
    defp iana_latitudes do
      case Path.wildcard(Path.join(Tz.IanaDataDir.dir(), "**/zone1970.tab")) do
        [] ->
          :no_data

        [path | _rest] ->
          path
          |> File.read!()
          |> String.split("\n", trim: true)
          |> Enum.reject(&String.starts_with?(&1, "#"))
          |> Enum.flat_map(&territory_latitude(&1))
          |> Enum.reduce(%{}, fn {territory, latitude}, acc ->
            Map.put_new(acc, territory, latitude)
          end)
      end
    end

    defp territory_latitude(line) do
      case String.split(line, "\t") do
        [codes, coordinates | _rest] ->
          [first | _keep_its_time] = String.split(codes, ",")
          [{String.to_atom(first), latitude(coordinates)}]

        _not_a_zone_line ->
          []
      end
    end

    # ISO 6709: a sign, two digits of latitude degrees and two of minutes,
    # then the longitude, which is not needed here.
    defp latitude(<<sign::binary-1, degrees::binary-2, minutes::binary-2, _longitude::binary>>) do
      magnitude = String.to_integer(degrees) + String.to_integer(minutes) / 60

      case sign do
        "-" -> -magnitude
        _north -> magnitude
      end
    end
  end
end
