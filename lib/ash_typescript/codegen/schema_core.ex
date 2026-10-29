# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.SchemaCore do
  @moduledoc """
  Shared logic for schema generation across all validation library targets.

  All resource introspection, topological sorting, field resolution, and structural
  code generation lives here. Output syntax is delegated to a module implementing
  `AshTypescript.Codegen.SchemaFormatter`.

  Consumers (e.g. `ZodSchemaGenerator`) pass `__MODULE__` as the first `formatter`
  argument to each public function.
  """

  alias Ash.Info.Manifest.Type, as: SpecType
  alias AshTypescript.Codegen.{ClientNames, CustomTypeAliases}
  alias AshTypescript.Codegen.Helpers, as: CodegenHelpers
  alias AshTypescript.CustomTypes
  alias AshTypescript.CustomTypes.{MapType, Scalar}
  alias AshTypescript.Manifest.Custom
  alias AshTypescript.Rpc.Codegen.Helpers.ActionIntrospection
  alias AshTypescript.TypeSystem.Introspection

  import AshTypescript.Helpers

  # Ash.Info.Manifest.Type kinds → corresponding Ash type module, used to look up
  # static primitive schemas in `formatter.simple_primitives()`. Only listed
  # for kinds that have a 1:1 module correspondence and don't need
  # constraint-driven formatting (string/integer/float/atom/etc. are handled
  # directly by their kind in the dispatch).
  @kind_to_ash_module %{
    boolean: Ash.Type.Boolean,
    uuid: Ash.Type.UUID,
    date: Ash.Type.Date,
    time: Ash.Type.Time,
    time_usec: Ash.Type.TimeUsec,
    datetime: Ash.Type.DateTime,
    utc_datetime: Ash.Type.UtcDatetime,
    utc_datetime_usec: Ash.Type.UtcDatetimeUsec,
    naive_datetime: Ash.Type.NaiveDatetime,
    duration: Ash.Type.Duration,
    decimal: Ash.Type.Decimal,
    binary: Ash.Type.Binary,
    term: Ash.Type.Term
  }

  # Ash `storage_type/1` results → corresponding Ash type module, used to derive
  # a schema for hand-rolled custom types that match nothing else. Only
  # storage types with an unambiguous JSON wire form are listed; anything else
  # resolves to the formatter's `any_schema()`.
  @storage_to_ash_module %{
    boolean: Ash.Type.Boolean,
    uuid: Ash.Type.UUID,
    binary_id: Ash.Type.UUID,
    date: Ash.Type.Date,
    time: Ash.Type.Time,
    time_usec: Ash.Type.TimeUsec,
    naive_datetime: Ash.Type.NaiveDatetime,
    utc_datetime: Ash.Type.UtcDatetime,
    utc_datetime_usec: Ash.Type.UtcDatetimeUsec,
    decimal: Ash.Type.Decimal,
    binary: Ash.Type.Binary
  }

  # ─────────────────────────────────────────────────────────────────
  # Core Type Mapping (dispatches on %Ash.Info.Manifest.Type{})
  # ─────────────────────────────────────────────────────────────────

  # Recursive dispatch — assumes input is already an `%Ash.Info.Manifest.Type{}`.
  # Strings enforce non-emptiness whenever their folded constraints carry
  # `allow_empty?: false` (the Ash string default), mirroring what the server
  # accepts — independent of the field's nilability.
  #
  # Options:
  #
  #   * `custom_fields?` is true for a member of a declared custom type's
  #     definition: a scalar entry's base mapping then uses the member's own
  #     constraints. It follows arrays, and nested containers set their own.
  #   * `lazy?` defers references to resource schemas (`wrap_lazy/1`), for the
  #     named custom-type schemas, which come before the resource schemas. It
  #     follows every nested type.
  defp map_spec_type(formatter, type_info, opts \\ [])

  defp map_spec_type(_formatter, nil, _opts), do: nil

  defp map_spec_type(formatter, %SpecType{} = type_info, opts) do
    case type_info.kind do
      kind when kind in [:string, :ci_string] ->
        constraints = type_info.constraints || []
        formatter.format_string(constraints, require_non_empty?(constraints))

      :integer ->
        formatter.format_integer(type_info.constraints || [])

      :float ->
        formatter.format_float(type_info.constraints || [])

      :atom ->
        # Atom without `one_of` (which becomes :enum). Plain string.
        formatter.format_string([], false)

      :enum ->
        format_enum_values(formatter, type_info.values || [])

      :array ->
        # Item constraints already live on `item_type`; `type_info.constraints`
        # carries the array's own cardinality (`min_length`/`max_length`), which
        # the formatter renders alongside the item schema.
        inner = map_spec_type(formatter, type_info.item_type, opts) || formatter.any_schema()

        formatter.format_array(inner, type_info.constraints || [])

      :union ->
        map_spec_union(formatter, type_info, opts)

      kind when kind in [:resource, :embedded_resource] ->
        map_resource_ref(formatter, SpecType.effective_resource(type_info), opts)

      kind when kind in [:map, :keyword, :tuple, :struct] ->
        map_typed_container(formatter, type_info, opts)

      :type_ref ->
        map_type_ref(formatter, type_info, opts)

      :unknown ->
        map_unknown_module(formatter, type_info, Keyword.get(opts, :custom_fields?, false))

      _primitive_kind ->
        lookup_primitive(formatter, type_info)
    end
  end

  # A named type: its entry's replacement, else the definition's named
  # custom-type schema, else the definition inline.
  defp map_type_ref(formatter, %SpecType{} = type_info, opts) do
    with nil <- map_entry_schema(formatter, type_info) do
      definition = Introspection.named_type_definition(type_info.module)

      custom_type_schema_name(formatter, definition) ||
        map_spec_type(formatter, definition, nested_opts(opts))
    end
  end

  # The options a nested type inherits: `custom_fields?` is the container's.
  defp nested_opts(opts), do: Keyword.take(opts, [:lazy?])

  # Leaf lookup, mirroring the precedence `TypeMapper.map_type/3` documents:
  # the type's own module wins over the kind table. `kind` is a coarse bucket
  # while `module` is the precise identity — Ash files several distinct builtins
  # under `kind: :term` (`Term`, `File`, `Function`, `Vector`), so resolving by
  # kind alone collapses them all onto `Ash.Type.Term`.
  defp lookup_primitive(formatter, %SpecType{module: module, kind: kind}) do
    cond do
      module && Map.has_key?(formatter.simple_primitives(), module) ->
        Map.get(formatter.simple_primitives(), module)

      (mapped_module = Map.get(@kind_to_ash_module, kind)) != nil ->
        Map.get(formatter.simple_primitives(), mapped_module, formatter.any_schema())

      true ->
        formatter.any_schema()
    end
  end

  # A declared custom type's `map` entry (the manifest's, else the built-in)
  # replaces the object of its fields with its `zod` / `valibot`, when it has
  # one for this formatter's library. A NewType that inherits its subtype's
  # fields (no entry or `typescript_fields/0` of its own) inherits its
  # subtype's entry too.
  defp map_entry_schema(formatter, %SpecType{module: module} = type_info) do
    case CustomTypes.map_entry(module, &Custom.custom_type_entry(nil, &1)) do
      %MapType{} = entry -> CustomTypes.mapping(entry, formatter.library(), type_info.constraints)
      nil -> nil
    end
  end

  # Handles `:unknown` kinds — hand-rolled `use Ash.Type` modules:
  #
  #   1. a `scalar` entry in the manifest's `custom_types` section;
  #   2. the formatter's `simple_primitives`;
  #   3. a built-in `scalar` entry (`AshTypescript.CustomTypes.Builtin`);
  #   4. for a type with `typescript_type/0`, a schema derived from its
  #      `storage_type/1` rather than a flat string — a custom type storing
  #      `:integer` validates as a number, not as text.
  #
  # An `Ash.Type.NewType` resolves to its subtype's kind (or a `:type_ref`)
  # and carries its declared constraints through the normal dispatch, so it
  # never lands here. `typescript_type/0` has no schema counterpart, so it
  # doesn't replace a built-in's schema.
  defp map_unknown_module(formatter, %SpecType{module: module} = type_info, custom_fields?) do
    cond do
      match?(%Scalar{}, entry = Custom.declared_custom_type(nil, module)) ->
        scalar_schema(formatter, entry, type_info, custom_fields?)

      module && Map.has_key?(formatter.simple_primitives(), module) ->
        Map.get(formatter.simple_primitives(), module)

      match?(%Scalar{}, entry = Custom.builtin_custom_type(nil, module)) ->
        scalar_schema(formatter, entry, type_info, custom_fields?)

      module && Introspection.is_custom_type?(module) ->
        storage_derived_schema(formatter, module)

      true ->
        formatter.any_schema()
    end
  end

  # The entry's `zod` / `valibot` (an MFA gets the node's constraints), else
  # its base type with the entry's constraints, or the node's for a member of
  # a declared custom type (whose definition carries them merged).
  defp scalar_schema(formatter, %Scalar{} = entry, type_info, custom_fields?) do
    case CustomTypes.mapping(entry, formatter.library(), type_info.constraints) do
      nil ->
        map_spec_type(
          formatter,
          CustomTypes.base_type(entry, type_info.constraints, custom_fields?)
        )

      schema ->
        schema
    end
  end

  # Derives a schema from the type's Ash storage type. Unrecognized storage
  # falls through to the permissive `any_schema()` rather than guessing — a
  # wrong schema rejects valid data, which is worse than not validating.
  defp storage_derived_schema(formatter, module) do
    storage_schema(formatter, Ash.Type.storage_type(module))
  rescue
    _ -> formatter.any_schema()
  end

  defp storage_schema(formatter, {:array, inner}),
    do: formatter.format_array(storage_schema(formatter, inner), [])

  defp storage_schema(formatter, :integer), do: formatter.format_integer([])
  defp storage_schema(formatter, :float), do: formatter.format_float([])

  defp storage_schema(formatter, storage) when storage in [:string, :ci_string, :atom],
    do: formatter.format_string([], false)

  defp storage_schema(formatter, storage) when storage in [:map, :jsonb],
    do: formatter.wrap_record()

  defp storage_schema(formatter, storage) do
    case Map.get(@storage_to_ash_module, storage) do
      nil -> formatter.any_schema()
      mapped -> Map.get(formatter.simple_primitives(), mapped, formatter.any_schema())
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Public API — type resolution
  # ─────────────────────────────────────────────────────────────────

  @doc """
  Maps a type-bearing spec input to a schema string.

  Accepted shapes (all `%Ash.Info.Manifest.*{}`):
  - `%Ash.Info.Manifest.Type{}` — the canonical spec form
  - `%Ash.Info.Manifest.Argument{}` / `%Ash.Info.Manifest.Field{}` — anything with a
    `:type` field carrying a `%Ash.Info.Manifest.Type{}`
  - Aggregate kind atoms (e.g. `:count`, `:sum`) — looked up in
    `formatter.aggregate_types()`

  Callers must feed spec data. Raw Ash types (atom modules, `{:array, _}`
  tuples, `%{type: SomeType, constraints: [...]}` shapes) are no longer
  accepted; resolve via `Ash.Info.Manifest.Generator.TypeResolver.resolve/2` first.

  Non-empty enforcement for string types is constraint-driven: whenever the
  string's folded constraints carry `allow_empty?: false` (the Ash default),
  the schema gets an effective min-length 1 (unless an explicit `:min_length`
  is set) — matching server-side validation regardless of the field's
  nilability. Strings with `allow_empty?: true` stay unconstrained. This
  applies uniformly, including nested string fields inside typed containers.
  """
  def get_type(formatter, type_input, context \\ nil)

  def get_type(formatter, kind, _context) when is_atom(kind) and not is_nil(kind) do
    Map.get(formatter.aggregate_types(), kind, formatter.any_schema())
  end

  def get_type(formatter, %SpecType{} = type_info, _context) do
    map_spec_type(formatter, type_info)
  end

  def get_type(formatter, %{type: %SpecType{} = type_info}, _context) do
    map_spec_type(formatter, type_info)
  end

  # Ash strings default to `allow_empty?: false`, and the manifest folds that
  # default into every resolved string type's constraints. Only an explicit
  # `allow_empty?: false` triggers enforcement so that non-Ash-string contexts
  # (atoms rendered as strings, constraint-less inputs) stay unconstrained.
  defp require_non_empty?(constraints) do
    Keyword.get(constraints, :allow_empty?) == false
  end

  @doc """
  Computes the effective minimum length for a string schema.

  Shared by the Zod and Valibot formatters so the rule cannot drift: an
  explicit `:min_length` replaces the implicit non-empty minimum — but when
  the string is non-empty (`allow_empty?: false`), the minimum is floored at
  1, since the server nulls `""` regardless of a declared `min_length: 0`.
  Returns `nil` when no minimum applies.
  """
  def effective_min_length(constraints, require_non_empty) do
    min_length = Keyword.get(constraints, :min_length)

    if require_non_empty do
      max(min_length || 1, 1)
    else
      min_length
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Public API — schema generation
  # ─────────────────────────────────────────────────────────────────

  @doc """
  Whether an RPC action gets an input schema at all.

  An action with no inputs produces no schema, so anything that advertises or
  re-exports a schema name must ask this first — otherwise it points consumers
  at an export that does not exist.
  """
  def action_has_schema?(action) do
    ActionIntrospection.action_input_type(action) != :none
  end

  @doc """
  Returns the exported schema constant name for an RPC action's input.

  Single source of truth for the name — used by `generate_action_schema/4` (the
  export itself), the namespace re-export collection, and both manifests, so
  they cannot drift from the configured `*_schema_suffix`.
  """
  def action_schema_name(formatter, rpc_action_name) do
    format_output_field("#{rpc_action_name}#{formatter.schema_suffix()}")
  end

  @doc """
  Generates a schema definition for an RPC action's input.
  Returns an empty string when the action has no input.
  """
  def generate_action_schema(formatter, resource, action, rpc_action_name) do
    if action_has_schema?(action) do
      schema_name = action_schema_name(formatter, rpc_action_name)

      field_defs =
        Enum.map(action.inputs, &process_input_field(formatter, resource, action, &1))

      field_lines = Enum.map(field_defs, fn {name, type} -> "  #{name}: #{type}," end)
      kw = formatter.library_prefix()

      """
      export const #{schema_name} = #{kw}.object({
      #{Enum.join(field_lines, "\n")}
      });
      """
    else
      ""
    end
  end

  @doc """
  Generates schemas for a list of resources (embedded resources, struct args).
  Returns an empty string when generation is disabled or the list is empty.

  Every resource must be in the manifest (`AshTypescript.resource_lookup/0`,
  `AshTypescript.with_manifest/2` applies), since field names come from its
  decoration; a missing one raises `ArgumentError`.
  """
  def generate_schemas_for_resources(formatter, resources) do
    if formatter.generate_schemas_enabled?() and resources != [] do
      uniq_resources = Enum.uniq(resources)
      resource_lookup = manifest_lookup!(uniq_resources)

      schemas =
        uniq_resources
        |> topological_sort(resource_lookup)
        |> Enum.map_join("\n\n", &generate_schema_for_resource(formatter, &1, resource_lookup))

      """
      // ============================
      // #{formatter.section_header()}
      // ============================

      #{schemas}
      """
    else
      ""
    end
  end

  @doc "Generates a schema for a single resource."
  def generate_schema_for_resource(formatter, resource, resource_lookup \\ nil) do
    lookup = resource_lookup || manifest_lookup!([resource])
    generate_schema_impl(formatter, resource, lookup)
  end

  @doc """
  The name of a declared custom type's named schema for `formatter`'s
  library: its TypeScript alias followed by the configured `schema_suffix/0`
  (`MoneyZodSchema`). `nil` when it has none: a `zod` / `valibot`
  replacement, a definition that reaches a non-embedded resource
  (`AshTypescript.Codegen.CustomTypeAliases.reaches_resource?/1`: such a
  resource has no schema to reference), or one that isn't a declared custom
  type.
  """
  @spec custom_type_schema_name(module(), SpecType.t()) :: String.t() | nil
  def custom_type_schema_name(formatter, %SpecType{} = definition) do
    name = CustomTypeAliases.plain_name(definition)

    cond do
      is_nil(name) -> nil
      is_nil(Map.fetch!(Custom.type_alias_names(definition), formatter.library())) -> nil
      CustomTypeAliases.reaches_resource?(definition) -> nil
      true -> name <> formatter.schema_suffix()
    end
  end

  @doc """
  The named custom-type schemas for `formatter`, as `%{schema_name => module}`.
  """
  @spec custom_type_schema_names(module()) :: %{String.t() => module()}
  def custom_type_schema_names(formatter) do
    formatter
    |> custom_type_schema_definitions()
    |> Map.new(fn {name, definition} -> {name, definition.module} end)
  end

  @doc """
  Generates the named schemas of the declared custom types (manifest
  definitions with `AshRpc.Manifest.Custom.custom_type?/1` and a schema name,
  `custom_type_schema_name/2`), under a "Schemas for Custom Types" section
  header. Returns `""` when there are none.

  The section goes before the resource schemas, so every later schema can
  reference the names. Each schema follows the named schemas its fields
  reference (Kahn's algorithm, ties by name); references to resource schemas
  are deferred with `wrap_lazy/1`. Named schemas that reference each other in
  a cycle throw `{:error, message}`
  (`AshTypescript.Codegen.CustomTypeAliases.recursion_message/1`); codegen
  rejects recursive declared types before rendering any schema
  (`CustomTypeAliases.check_recursive_types!/0`).

  Definitions are read from the configured manifest
  (`AshTypescript.with_manifest/2` applies).
  """
  @spec generate_custom_type_schemas(module()) :: String.t()
  def generate_custom_type_schemas(formatter) do
    case custom_type_schema_definitions(formatter) do
      [] ->
        ""

      named ->
        schemas =
          named
          |> sort_custom_type_schemas(formatter)
          |> Enum.map_join("\n", fn {name, definition} ->
            "export const #{name} = #{map_spec_type(formatter, definition, lazy?: true)};"
          end)

        """
        // ============================
        // #{formatter.library_name()} Schemas for Custom Types
        // ============================

        #{schemas}
        """
    end
  end

  defp custom_type_schema_definitions(formatter) do
    AshTypescript.manifest().types
    |> Enum.flat_map(fn definition ->
      case custom_type_schema_name(formatter, definition) do
        nil -> []
        name -> [{name, definition}]
      end
    end)
  end

  defp sort_custom_type_schemas(named, formatter) do
    by_module =
      Map.new(named, fn {name, definition} -> {definition.module, {name, definition}} end)

    modules = Map.keys(by_module)

    deps_map =
      Map.new(named, fn {_name, definition} ->
        {definition.module, custom_type_schema_deps(formatter, definition, by_module)}
      end)

    {sorted, remaining} = kahns_sort(modules, deps_map, &elem(Map.fetch!(by_module, &1), 0))

    if MapSet.size(remaining) == 0 do
      Enum.map(sorted, &Map.fetch!(by_module, &1))
    else
      throw({:error, CustomTypeAliases.recursion_message(remaining)})
    end
  end

  # The named custom-type schemas a definition's fields reference, through
  # arrays, union members, inline typed containers and inline (unnamed)
  # named types. Resource schemas aren't dependencies: they're referenced
  # lazily. A recursion through a named schema ends at its name; one among
  # inline types only would not terminate when rendered either.
  defp custom_type_schema_deps(formatter, %SpecType{} = definition, by_module) do
    definition
    |> SpecType.get_fields()
    |> Enum.flat_map(&schema_deps(formatter, &1.type, by_module))
    |> Enum.uniq()
  end

  defp schema_deps(formatter, %SpecType{kind: :type_ref, module: module} = type, by_module) do
    cond do
      map_entry_schema(formatter, type) != nil -> []
      Map.has_key?(by_module, module) -> [module]
      true -> schema_deps(formatter, Introspection.named_type_definition(module), by_module)
    end
  end

  defp schema_deps(formatter, %SpecType{kind: :array, item_type: item}, by_module),
    do: schema_deps(formatter, item, by_module)

  defp schema_deps(formatter, %SpecType{kind: :union} = union, by_module),
    do: Enum.flat_map(union.members || [], &schema_deps(formatter, &1.type, by_module))

  defp schema_deps(formatter, %SpecType{kind: kind} = container, by_module)
       when kind in [:map, :keyword, :tuple, :struct] do
    container
    |> SpecType.get_fields()
    |> Enum.flat_map(&schema_deps(formatter, &1.type, by_module))
  end

  defp schema_deps(_formatter, _type, _by_module), do: []

  defp manifest_lookup!(resources) do
    lookup = AshTypescript.resource_lookup()

    case Enum.reject(resources, &Map.has_key?(lookup, &1)) do
      [] ->
        lookup

      missing ->
        raise ArgumentError,
              "resources #{inspect(missing)} are not in the manifest; schemas are named " <>
                "from decorated manifest resources only"
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Regex utilities (shared by both formatters)
  # ─────────────────────────────────────────────────────────────────

  @doc "Returns true when a regex source string is safe to emit as a JS literal."
  def regex_safe_for_js?(source) do
    pcre_only_patterns = [
      ~r/\(\?<[!=]/,
      ~r/[*+?]\+/,
      ~r/\(\?>/,
      ~r/\(\?P</,
      ~r/\(\?[imsxADSUXJ]/,
      ~r/\(\?R\)/,
      ~r/\(\?[0-9]/,
      ~r/\(\?\([^)]+\)/,
      ~r/\\[AG]/,
      ~r/\\[pP]\{/
    ]

    not Enum.any?(pcre_only_patterns, &Regex.match?(&1, source))
  end

  @doc "Builds a JS regex flag string from Elixir Regex opts."
  def build_js_flags(opts) do
    []
    |> then(fn flags -> if :caseless in opts, do: ["i" | flags], else: flags end)
    |> then(fn flags -> if :multiline in opts, do: ["m" | flags], else: flags end)
    |> then(fn flags -> if :dotall in opts, do: ["s" | flags], else: flags end)
    |> Enum.join()
  end

  # ─────────────────────────────────────────────────────────────────
  # Private — type-specific dispatch
  # ─────────────────────────────────────────────────────────────────

  defp map_typed_container(formatter, %SpecType{} = type_info, opts) do
    fields = SpecType.get_fields(type_info)

    cond do
      fields != [] ->
        build_object_from_fields(formatter, type_info, fields, opts)

      type_info.kind == :struct and type_info.instance_of != nil and
          Spark.Dsl.is?(type_info.instance_of, Ash.Resource) ->
        map_resource_ref(formatter, type_info.instance_of, opts)

      type_info.kind == :struct and type_info.instance_of != nil ->
        formatter.wrap_object("")

      true ->
        formatter.wrap_record()
    end
  end

  defp map_resource_ref(formatter, resource, opts) do
    resource_name = CodegenHelpers.build_resource_type_name(resource)
    name = "#{resource_name}#{formatter.schema_suffix()}"

    if Keyword.get(opts, :lazy?, false), do: formatter.wrap_lazy(name), else: name
  end

  defp format_enum_values(formatter, values) do
    enum_values =
      values
      |> Enum.sort_by(&to_string/1)
      |> Enum.map_join(", ", &"\"#{to_string(&1)}\"")

    formatter.format_enum(enum_values)
  end

  # ─────────────────────────────────────────────────────────────────
  # Private — object / union builders (spec-typed)
  # ─────────────────────────────────────────────────────────────────

  # Field names come from the container's decoration.
  defp build_object_from_fields(formatter, %SpecType{} = container, fields, opts) do
    field_opts =
      [custom_fields?: AshRpc.Manifest.Custom.custom_type?(container)] ++ nested_opts(opts)

    field_schemas =
      Enum.map_join(fields, ", ", fn %{
                                       name: field_name,
                                       type: %SpecType{} = field_type,
                                       allow_nil?: allow_nil
                                     } ->
        schema_type = map_spec_type(formatter, field_type, field_opts)
        schema_type = maybe_wrap_nullable_optional(formatter, schema_type, allow_nil, allow_nil)

        "#{ClientNames.type_field(container, field_name)}: #{schema_type}"
      end)

    formatter.wrap_object(field_schemas)
  end

  defp map_spec_union(formatter, %SpecType{} = union, opts) do
    case union.members || [] do
      [] ->
        formatter.any_schema()

      members ->
        union_schemas =
          Enum.map_join(members, ", ", fn %{name: name, type: %SpecType{} = type} ->
            formatted_name = ClientNames.union_member(union, name)
            schema_type = map_spec_type(formatter, type, nested_opts(opts))
            formatter.wrap_object("#{formatted_name}: #{schema_type}")
          end)

        formatter.wrap_union(union_schemas)
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Private — field processing
  # ─────────────────────────────────────────────────────────────────

  defp process_input_field(formatter, resource, action, input) do
    formatted_name = ClientNames.action_input(resource, action, input.name)

    compose_input_field(formatter, formatted_name, input, input.allow_nil?, not input.required?)
  end

  @doc """
  Composes a single input-field schema entry: resolves the field's type
  through the formatter, then wraps nullable/optional.

  This is the one place that knows how "input argument -> schema field"
  works — shared by RPC action input schemas (above) and typed-controller
  route argument schemas (`RouteRenderer`), so the two surfaces cannot drift.
  """
  def compose_input_field(formatter, formatted_name, input, nullable?, omittable?) do
    schema_type = get_type(formatter, input)
    schema_type = maybe_wrap_nullable_optional(formatter, schema_type, nullable?, omittable?)
    {formatted_name, schema_type}
  end

  @doc """
  Wraps a schema string with `wrap_nullable` (innermost) and/or `wrap_optional`
  (outermost) based on the two booleans, using the given formatter.
  """
  def maybe_wrap_nullable_optional(formatter, schema, nullable?, omittable?) do
    schema = if nullable?, do: formatter.wrap_nullable(schema), else: schema
    if omittable?, do: formatter.wrap_optional(schema), else: schema
  end

  # ─────────────────────────────────────────────────────────────────
  # Private — resource schema generation
  # ─────────────────────────────────────────────────────────────────

  defp generate_schema_impl(formatter, resource, resource_lookup) do
    resource_name = CodegenHelpers.build_resource_type_name(resource)
    schema_name = "#{resource_name}#{formatter.schema_suffix()}"
    kw = formatter.library_prefix()
    api_resource = Ash.Info.Manifest.get_resource!(resource_lookup, resource)

    fields =
      api_resource
      |> Ash.Info.Manifest.Resource.fields_by_kind(:attribute)
      |> Enum.map_join("\n", fn attr ->
        formatted_name = ClientNames.resource_field(api_resource, attr.name)
        schema_type = get_type(formatter, attr)
        nullable = attr.allow_nil?
        omittable = attr.allow_nil? || attr.has_default?
        schema_type = maybe_wrap_nullable_optional(formatter, schema_type, nullable, omittable)

        "  #{formatted_name}: #{schema_type},"
      end)

    """
    export const #{schema_name} = #{kw}.object({
    #{fields}
    });
    """
  end

  # ─────────────────────────────────────────────────────────────────
  # Private — topological sort (Kahn's algorithm)
  # ─────────────────────────────────────────────────────────────────

  defp topological_sort(resources, resource_lookup) do
    resource_set = MapSet.new(resources)

    deps_map =
      Map.new(resources, fn resource ->
        {resource, find_resource_dependencies(resource, resource_set, resource_lookup)}
      end)

    {sorted, remaining} = kahns_sort(resources, deps_map, &inspect/1)

    sorted ++ Enum.filter(resources, &MapSet.member?(remaining, &1))
  end

  # Returns `{sorted, remaining}`: `remaining` is non-empty when there's a
  # cycle. Nodes that become ready together are ordered by `sort_key`.
  defp kahns_sort(nodes, deps_map, sort_key) do
    do_kahns_sort([], MapSet.new(nodes), deps_map, sort_key)
  end

  defp do_kahns_sort(sorted, remaining, deps_map, sort_key) do
    ready =
      remaining
      |> Enum.filter(fn node ->
        deps = Map.get(deps_map, node, [])
        Enum.all?(deps, fn dep -> not MapSet.member?(remaining, dep) end)
      end)
      |> Enum.sort_by(sort_key)

    case ready do
      [] ->
        {sorted, remaining}

      _ ->
        new_remaining = Enum.reduce(ready, remaining, &MapSet.delete(&2, &1))
        do_kahns_sort(sorted ++ ready, new_remaining, deps_map, sort_key)
    end
  end

  defp find_resource_dependencies(resource, resource_set, resource_lookup) do
    api_resource = Ash.Info.Manifest.get_resource!(resource_lookup, resource)

    api_resource
    |> Ash.Info.Manifest.Resource.fields_by_kind(:attribute)
    |> Enum.flat_map(fn attr -> extract_resource_deps_from_spec(attr.type, resource_set) end)
    |> Enum.uniq()
  end

  # Walks a resolved `%Ash.Info.Manifest.Type{}` and returns the embedded/instance_of
  # resource modules it depends on (those present in `resource_set`).
  defp extract_resource_deps_from_spec(%SpecType{kind: :array, item_type: item}, resource_set) do
    extract_resource_deps_from_spec(item, resource_set)
  end

  defp extract_resource_deps_from_spec(
         %SpecType{kind: :embedded_resource, resource_module: mod},
         resource_set
       )
       when not is_nil(mod) do
    if MapSet.member?(resource_set, mod), do: [mod], else: []
  end

  defp extract_resource_deps_from_spec(
         %SpecType{kind: :resource, resource_module: mod},
         resource_set
       )
       when not is_nil(mod) do
    if MapSet.member?(resource_set, mod), do: [mod], else: []
  end

  defp extract_resource_deps_from_spec(
         %SpecType{kind: :struct, instance_of: inst},
         resource_set
       )
       when not is_nil(inst) do
    if Spark.Dsl.is?(inst, Ash.Resource) and MapSet.member?(resource_set, inst),
      do: [inst],
      else: []
  end

  defp extract_resource_deps_from_spec(_type, _resource_set), do: []
end
