defmodule Localize.Locale.DistanceTrie do
  @moduledoc false

  # A 3-level nested map of TR35's language matching distances
  # (`languageMatching` in `languageInfo.xml`), arranged as ICU's
  # XLocaleDistance trie is, for locale distance lookups.
  #
  # The trie is keyed by {desired, supported} tuples at each level.
  # Wildcard entries use :* and negative variable entries use
  # {:not_in, variable} which are checked at lookup time.

  @persistent_term_key {:localize, :distance_trie}

  @empty_not_in_index %{desired: %{}, supported: %{}, both: []}

  @doc false
  @spec lookup(String.t(), atom(), atom(), String.t(), atom(), atom()) :: number()
  # The trie walk: match/wildcard/default fallbacks at each of the
  # language, script, and territory levels, as TR35's language matching
  # compares them.
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def lookup(
        desired_lang,
        desired_script,
        desired_territory,
        supported_lang,
        supported_script,
        supported_territory
      ) do
    {trie, variables, macro_regions} = ensure_loaded()
    default_lang_node = Map.get(trie, {:*, :*}) || %{distance: 0, script: %{}}

    # Language level
    {lang_distance, lang_node} =
      if desired_lang == supported_lang do
        node =
          cascade_lookup(trie, desired_lang, supported_lang, nil, nil, variables) ||
            default_lang_node

        {0, node}
      else
        node =
          cascade_lookup(trie, desired_lang, supported_lang, nil, nil, variables) ||
            default_lang_node

        distance = node[:distance] || default_lang_node.distance
        {distance, node}
      end

    # Script level — check lang_node's table, fall back to default
    script_table = lang_node[:script] || %{}
    default_script_table = default_lang_node[:script] || %{}

    {script_distance, script_node} =
      if desired_script == supported_script do
        node =
          cascade_lookup(script_table, desired_script, supported_script, nil, nil, variables) ||
            cascade_lookup(
              default_script_table,
              desired_script,
              supported_script,
              nil,
              nil,
              variables
            )

        {0, node}
      else
        node =
          cascade_lookup(script_table, desired_script, supported_script, nil, nil, variables) ||
            cascade_lookup(
              default_script_table,
              desired_script,
              supported_script,
              nil,
              nil,
              variables
            )

        cond do
          node && node[:distance] -> {node.distance, node}
          node -> {default_script_table[{:*, :*}][:distance] || 0, node}
          true -> {0, nil}
        end
      end

    # Territory level
    default_script_node =
      Map.get(script_table, {:*, :*}) ||
        Map.get(default_script_table, {:*, :*}) ||
        %{distance: 0, territory: %{}}

    territory_distance =
      if desired_territory == supported_territory do
        0
      else
        territory_distance(
          {territory_rules(script_node), territory_rules(default_script_node)},
          macro_regions,
          desired_territory,
          supported_territory
        )
      end

    lang_distance + script_distance + territory_distance
  end

  # A macro-region whose regions the rules treat in more than one way, such
  # as `001`, stands for one region of each such way, and its distance is
  # the largest of theirs, as ICU's `LocaleDistance` takes "the maximum
  # distance" over a region's partitions. `en-001` is then as far from
  # `en-GB` as from `en`, where reading `001` as outside `$enUS` put it
  # nearer `en-GB`.
  defp territory_distance({rules, default_rules}, macro_regions, desired, supported) do
    for desired_region <- Map.get(macro_regions, desired, [desired]),
        supported_region <- Map.get(macro_regions, supported, [supported]),
        reduce: 0 do
      distance ->
        max(
          distance,
          resolve_territory_distance(rules, default_rules, desired_region, supported_region)
        )
    end
  end

  # A script node's territory table, with the index of its "not in" rules.
  defp territory_rules(nil) do
    {%{}, @empty_not_in_index}
  end

  defp territory_rules(script_node) do
    {script_node[:territory] || %{}, script_node[:not_in] || @empty_not_in_index}
  end

  defp resolve_territory_distance(territory_rules, default_rules, desired, supported) do
    case territory_cascade_lookup(territory_rules, desired, supported) do
      nil ->
        case territory_cascade_lookup(default_rules, desired, supported) do
          nil -> 0
          distance -> distance
        end

      distance ->
        distance
    end
  end

  # Territory-level cascade with variable-aware matching.
  # Tries in order: exact → {desired, :*} → {:*, supported} → not_in rules → {:*, :*}
  defp territory_cascade_lookup({table, not_in_index}, desired, supported) do
    Map.get(table, {desired, supported}) ||
      Map.get(table, {desired, :*}) ||
      Map.get(table, {:*, supported}) ||
      find_not_in_match(not_in_index, desired, supported) ||
      Map.get(table, {:*, :*})
  end

  # Check {:not_in, var} entries. Concrete + not_in combinations come first
  # (more specific), then not_in + not_in and not_in + :* (less specific).
  # Within each group the first rule in the table's own order wins, as the
  # index keeps that order.
  defp find_not_in_match(not_in_index, desired, supported) do
    find_not_in_concrete(not_in_index, desired, supported) ||
      find_not_in_both(not_in_index, desired, supported)
  end

  # One side is a concrete territory, the other is {:not_in, var}.
  defp find_not_in_concrete(%{desired: by_desired, supported: by_supported}, desired, supported) do
    first_not_in(Map.get(by_desired, desired, []), supported) ||
      first_not_in(Map.get(by_supported, supported, []), desired)
  end

  # Both sides are {:not_in, var}, or one is {:not_in, var} and the other :*.
  # A `nil` set stands for :*, which every territory matches.
  defp find_not_in_both(%{both: rules}, desired, supported) do
    Enum.find_value(rules, fn {desired_set, supported_set, distance} ->
      if outside?(desired, desired_set) and outside?(supported, supported_set) do
        distance
      end
    end)
  end

  defp first_not_in(rules, territory) do
    Enum.find_value(rules, fn {set, distance} ->
      if outside?(territory, set) do
        distance
      end
    end)
  end

  defp outside?(_territory, nil) do
    true
  end

  defp outside?(territory, set) do
    not MapSet.member?(set, territory)
  end

  # Cascade lookup for language and script levels (no variable matching needed)
  defp cascade_lookup(table, desired, supported, _desired_extra, _supported_extra, _variables) do
    Map.get(table, {desired, supported}) ||
      Map.get(table, {desired, :*}) ||
      Map.get(table, {:*, supported}) ||
      Map.get(table, {:*, :*})
  end

  defp ensure_loaded do
    # Not routed through DataLoader because build() itself calls
    # DataLoader.load to fetch supplemental data, which would
    # deadlock (GenServer calling itself). The check-then-act
    # pattern here is safe: build() is idempotent and the worst
    # case of a concurrent race is a redundant persistent_term.put.
    case :persistent_term.get(@persistent_term_key, :not_loaded) do
      :not_loaded ->
        result = build()
        :persistent_term.put(@persistent_term_key, result)
        result

      result ->
        result
    end
  end

  @doc false
  def build do
    data = Localize.SupplementalData.language_matching()
    rules = Map.fetch!(data, :language_match)
    variables = Map.fetch!(data, :match_variables)

    {lang_rules, script_rules, territory_rules} = partition_rules(rules)

    trie = %{}
    trie = insert_language_rules(trie, lang_rules)
    trie = insert_script_rules(trie, script_rules)
    trie = insert_territory_rules(trie, territory_rules, variables)
    trie = index_not_in_rules(trie, variables)
    {trie, variables, macro_regions(territory_rules, variables)}
  end

  # For each macro-region whose regions fall into more than one partition,
  # one region of each partition. Regions are in one partition when every
  # rule treats them alike: they are in the same region variables, and a
  # rule names neither (as `en_GB` is named) or names that one alone.
  defp macro_regions(territory_rules, variables) do
    named = named_regions(territory_rules)
    containers = Localize.SupplementalData.territory_containers()

    for container <- Map.keys(containers),
        representatives =
          container
          |> leaf_regions(containers)
          |> partition_representatives(variables, named),
        match?([_, _ | _], representatives),
        into: %{} do
      {container, representatives}
    end
  end

  # The regions a container holds that hold none themselves, through every
  # level of containment: `419` holds `029`, which holds `PR`.
  defp leaf_regions(region, containers) do
    case Map.fetch(containers, region) do
      {:ok, contents} -> Enum.flat_map(contents, &leaf_regions(&1, containers))
      :error -> [region]
    end
  end

  defp partition_representatives(regions, variables, named) do
    regions
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.group_by(&partition(&1, variables, named))
    |> Enum.map(fn {_partition, [first | _rest]} -> first end)
    |> Enum.sort()
  end

  defp partition(region, variables, named) do
    in_variables =
      for {name, members} <- variables, region in members, do: name

    {Enum.sort(in_variables), named_region(region, named)}
  end

  defp named_region(region, named) do
    if MapSet.member?(named, region) do
      region
    else
      nil
    end
  end

  # The regions a rule names itself rather than through a variable.
  defp named_regions(territory_rules) do
    for rule <- territory_rules,
        [_language, _script, region] <- [rule.desired, rule.supported],
        is_atom(region) and region != :*,
        into: MapSet.new() do
      region
    end
  end

  defp partition_rules(rules) do
    Enum.reduce(rules, {[], [], []}, fn rule, {lang, script, terr} ->
      case length(rule.desired) do
        1 -> {[rule | lang], script, terr}
        2 -> {lang, [rule | script], terr}
        3 -> {lang, script, [rule | terr]}
      end
    end)
    |> then(fn {l, s, t} -> {Enum.reverse(l), Enum.reverse(s), Enum.reverse(t)} end)
  end

  # ── Language level ─────────────────────────────────────────

  defp insert_language_rules(trie, rules) do
    Enum.reduce(rules, trie, fn rule, acc ->
      [desired_lang] = rule.desired
      [supported_lang] = rule.supported
      one_way = Map.get(rule, :one_way, false)
      distance = rule.distance

      acc = put_lang_entry(acc, desired_lang, supported_lang, distance)

      if one_way do
        acc
      else
        put_lang_entry(acc, supported_lang, desired_lang, distance)
      end
    end)
  end

  defp put_lang_entry(trie, desired, supported, distance) do
    key = {desired, supported}
    Map.put_new(trie, key, %{distance: distance, script: %{}})
  end

  # ── Script level ───────────────────────────────────────────

  defp insert_script_rules(trie, rules) do
    Enum.reduce(rules, trie, fn rule, acc ->
      [desired_lang, desired_script] = rule.desired
      [supported_lang, supported_script] = rule.supported
      one_way = Map.get(rule, :one_way, false)
      distance = rule.distance

      acc =
        put_script_entry(
          acc,
          desired_lang,
          supported_lang,
          desired_script,
          supported_script,
          distance
        )

      if one_way do
        acc
      else
        put_script_entry(
          acc,
          supported_lang,
          desired_lang,
          supported_script,
          desired_script,
          distance
        )
      end
    end)
  end

  defp put_script_entry(
         trie,
         desired_lang,
         supported_lang,
         desired_script,
         supported_script,
         distance
       ) do
    lang_key = {desired_lang, supported_lang}

    lang_node =
      Map.get(trie, lang_key) || Map.get(trie, {desired_lang, :*}) || %{distance: 0, script: %{}}

    script_key = {desired_script, supported_script}
    script_table = Map.get(lang_node, :script, %{})
    script_table = Map.put_new(script_table, script_key, %{distance: distance, territory: %{}})

    updated_node = Map.put(lang_node, :script, script_table)
    Map.put(trie, lang_key, updated_node)
  end

  # ── Territory level ────────────────────────────────────────

  defp insert_territory_rules(trie, rules, variables) do
    Enum.reduce(rules, trie, fn rule, acc ->
      insert_territory_rule(acc, rule, variables)
    end)
  end

  defp insert_territory_rule(trie, rule, variables) do
    [desired_lang, desired_script, desired_terr] = rule.desired
    [supported_lang, supported_script, supported_terr] = rule.supported
    one_way = Map.get(rule, :one_way, false)
    distance = rule.distance

    desired_keys = expand_territory_keys(desired_terr, variables)
    supported_keys = expand_territory_keys(supported_terr, variables)

    trie =
      put_territory_entries(
        trie,
        desired_lang,
        supported_lang,
        desired_script,
        supported_script,
        desired_keys,
        supported_keys,
        distance
      )

    if one_way do
      trie
    else
      put_territory_entries(
        trie,
        supported_lang,
        desired_lang,
        supported_script,
        desired_script,
        supported_keys,
        desired_keys,
        distance
      )
    end
  end

  defp put_territory_entries(
         trie,
         desired_lang,
         supported_lang,
         desired_script,
         supported_script,
         desired_keys,
         supported_keys,
         distance
       ) do
    for desired_key <- desired_keys, supported_key <- supported_keys, reduce: trie do
      acc ->
        put_territory_entry(
          acc,
          desired_lang,
          supported_lang,
          desired_script,
          supported_script,
          desired_key,
          supported_key,
          distance
        )
    end
  end

  # ── "Not in" rule index ────────────────────────────────────

  # A territory rule such as `{BR, {:not_in, :"$americas"}}` matches by
  # testing membership, so it cannot be found by key. Each script node
  # keeps those rules beside its territory table, grouped by their concrete
  # side and with each variable's territories in a set, so a lookup does
  # not walk the whole table (over 4,000 entries for Spanish and Portuguese)
  # to find them. Each group keeps the table's iteration order, so the
  # first matching rule is the one a walk of the table would find.
  defp index_not_in_rules(trie, variables) do
    Map.new(trie, fn {lang_key, lang_node} ->
      {lang_key, index_lang_node(lang_node, variables)}
    end)
  end

  defp index_lang_node(%{script: script_table} = lang_node, variables) do
    indexed =
      Map.new(script_table, fn {script_key, script_node} ->
        {script_key, index_script_node(script_node, variables)}
      end)

    %{lang_node | script: indexed}
  end

  defp index_lang_node(lang_node, _variables) do
    lang_node
  end

  defp index_script_node(%{territory: territory_table} = script_node, variables) do
    Map.put(script_node, :not_in, not_in_index(territory_table, variables))
  end

  defp index_script_node(script_node, _variables) do
    script_node
  end

  defp not_in_index(territory_table, variables) do
    sets =
      Map.new(variables, fn {variable, territories} -> {variable, MapSet.new(territories)} end)

    %{desired: by_desired, supported: by_supported, both: both} =
      Enum.reduce(territory_table, @empty_not_in_index, fn {key, distance}, index ->
        add_not_in_rule(index, key, distance, sets)
      end)

    %{
      desired: Map.new(by_desired, fn {territory, rules} -> {territory, Enum.reverse(rules)} end),
      supported:
        Map.new(by_supported, fn {territory, rules} -> {territory, Enum.reverse(rules)} end),
      both: Enum.reverse(both)
    }
  end

  defp add_not_in_rule(index, {{:not_in, desired}, {:not_in, supported}}, distance, sets) do
    rule = {Map.fetch!(sets, desired), Map.fetch!(sets, supported), distance}
    %{index | both: [rule | index.both]}
  end

  defp add_not_in_rule(index, {{:not_in, desired}, supported}, distance, sets) do
    set = Map.fetch!(sets, desired)
    index = %{index | supported: prepend(index.supported, supported, {set, distance})}

    if supported == :* do
      %{index | both: [{set, nil, distance} | index.both]}
    else
      index
    end
  end

  defp add_not_in_rule(index, {desired, {:not_in, supported}}, distance, sets) do
    set = Map.fetch!(sets, supported)
    index = %{index | desired: prepend(index.desired, desired, {set, distance})}

    if desired == :* do
      %{index | both: [{nil, set, distance} | index.both]}
    else
      index
    end
  end

  defp add_not_in_rule(index, _key, _distance, _sets) do
    index
  end

  defp prepend(groups, territory, rule) do
    Map.update(groups, territory, [rule], &[rule | &1])
  end

  # Expand territory patterns to trie keys.
  # {:in, var} expands to individual territory atoms.
  # {:not_in, var} stays as-is (checked at lookup time).
  # :* stays as :*.
  defp expand_territory_keys(:*, _variables), do: [:*]
  defp expand_territory_keys({:in, variable}, variables), do: Map.fetch!(variables, variable)
  defp expand_territory_keys({:not_in, _variable} = not_in, _variables), do: [not_in]
  defp expand_territory_keys(territory, _variables) when is_atom(territory), do: [territory]

  defp put_territory_entry(
         trie,
         desired_lang,
         supported_lang,
         desired_script,
         supported_script,
         desired_terr,
         supported_terr,
         distance
       ) do
    lang_key = {desired_lang, supported_lang}

    lang_node =
      Map.get(trie, lang_key) || Map.get(trie, {desired_lang, :*}) ||
        %{distance: nil, script: %{}}

    script_key = {desired_script, supported_script}
    script_table = Map.get(lang_node, :script, %{})

    script_node =
      Map.get(script_table, script_key) || Map.get(script_table, {desired_script, :*}) ||
        %{distance: nil, territory: %{}}

    terr_key = {desired_terr, supported_terr}
    territory_table = Map.get(script_node, :territory, %{})
    territory_table = Map.put_new(territory_table, terr_key, distance)

    updated_script_node = Map.put(script_node, :territory, territory_table)
    updated_script_table = Map.put(script_table, script_key, updated_script_node)
    updated_lang_node = Map.put(lang_node, :script, updated_script_table)
    Map.put(trie, lang_key, updated_lang_node)
  end
end
