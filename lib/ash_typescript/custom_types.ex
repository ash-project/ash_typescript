# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.CustomTypes do
  @moduledoc """
  The fields a custom `use Ash.Type` module declares, as the field specs
  `AshRpc.Manifest.Decorator.decorate/3` takes (`custom_type_fields:`).

  `fields_for/3` checks, in order:

    1. the manifest module's `custom_types` entry for the module: a `map`
       entry's fields (with their `client_name`), or `nil` for a `scalar` or
       a field-less `map` entry (one that opts a field-bearing NewType into
       an alias and declares no fields);
    2. the type's `typescript_fields/0`, named by its
       `typescript_field_names/0`;
    3. the built-in `map` entry (`AshTypescript.CustomTypes.Builtin`), named by
       `typescript_field_names/0` first and the entry's `client_name` second;
    4. for a NewType with none of these, steps 1-3 for
       `Ash.Type.NewType.subtype_of/1` (the NewType's `typescript_field_names/0`
       win over the subtype's);
    5. when `composite?/1` is true at the default constraints
       (`Ash.Type.init(module, [])`), `composite_types/1` at those constraints,
       as non-null fields named by `typescript_field_names/0` (a NewType's
       over its subtype's);
    6. otherwise `nil`.

  Whichever step supplies them, a field typed by a module with a `scalar`
  entry (the manifest's, else a built-in) gets the entry's constraints merged
  under its own (`Keyword.merge/2`, the field winning per key; under `items:`
  for an array). A `typescript_fields/0` result that isn't a list of
  `{name, opts}` specs is passed on as it is, for ash_rpc's decoration to
  reject with an `ArgumentError` naming the module.

  `AshTypescript.Manifest.Transformers.DecorateManifest` passes the manifest's
  entries and the built-ins; `AshTypescript.RpcMappingSource` passes only the
  built-ins.
  """

  alias Ash.Info.Manifest
  alias AshTypescript.Codegen
  alias AshTypescript.CustomTypes.{Builtin, Field, MapType, Scalar}
  alias AshTypescript.Helpers

  @type entries :: %{module() => Scalar.t() | MapType.t()}
  @type fields_fun :: (module() -> [AshRpc.MappingSource.field_spec()] | nil)

  @typedoc """
  The names codegen gives an aliased map-like type
  (`custom.ash_typescript.type_alias_names`): the TypeScript alias, and per
  schema library `:derive` (a named schema: the alias followed by the
  configured suffix) or `nil` (the entry's replacement, used at every use).
  """
  @type names :: %{
          typescript: String.t(),
          zod: :derive | nil,
          valibot: :derive | nil
        }

  @typedoc """
  The persisted `custom_types` (`NormalizeCustomTypes`): the manifest's
  entries, the built-ins, and the `alias_all_types?` section option.
  """
  @type custom_types :: %{
          required(:declared) => entries(),
          required(:builtin) => entries(),
          optional(:alias_all_types?) => boolean()
        }

  @identifier ~r/\A[A-Za-z_$][A-Za-z0-9_$]*\z/
  # Names TypeScript doesn't accept for an exported type or const: type
  # keywords, the JavaScript reserved words (strict mode included) and the
  # names a module can't bind (`await`, `eval`, `arguments`).
  @reserved_words ~w(
    any unknown never object string number boolean bigint symbol undefined
    break case catch class const continue debugger default delete do else enum
    export extends false finally for function if import in instanceof new null
    return super switch this throw true try typeof var void while with
    implements interface let package private protected public static yield
    await eval arguments
  )

  @base_hint "Declare its fields with a `map` entry in your manifest module's `custom_types` " <>
               "section, a `typescript_fields/0` callback on the type, or " <>
               "`composite?/1` + `composite_types/1`."

  @doc """
  The field specs `module` declares (see the module doc), or `nil`.
  `declared` and `builtin` map modules to their entries.
  """
  @spec fields_for(module(), entries(), entries()) :: [AshRpc.MappingSource.field_spec()] | nil
  def fields_for(module, declared, builtin) do
    {specs, _dependencies} = resolve(module, declared, builtin)
    specs
  end

  @doc false
  # The `custom_type_fields:` closure over persisted `custom_types`
  # (`%{declared: …, builtin: …}`), or over the built-ins alone for `nil`.
  @spec fields_fun(custom_types() | nil) :: fields_fun()
  def fields_fun(%{declared: declared, builtin: builtin}), do: &fields_for(&1, declared, builtin)
  def fields_fun(nil), do: fields_fun(builtin_only())

  @doc false
  # The hint closure over persisted `custom_types` (`%{declared: …, builtin: …}`),
  # or over the built-ins alone for `nil`: `hint/3` as a function of the module,
  # for ash_rpc's `custom_type_fields_hint:` and `hint:` options.
  @spec hint_fun(custom_types() | nil) :: (module() -> String.t())
  def hint_fun(%{declared: declared, builtin: builtin}), do: &hint(&1, declared, builtin)
  def hint_fun(nil), do: hint_fun(builtin_only())

  @doc false
  # The persisted `custom_types` of a manifest without declarations: the
  # built-ins, `alias_all_types?` off.
  @spec builtin_only() :: custom_types()
  def builtin_only, do: %{declared: %{}, builtin: Builtin.by_module(), alias_all_types?: false}

  @doc false
  # The type modules whose `typescript_fields/0` or `composite_types/1`
  # supplied the fields of a declared custom type in `manifest.types`
  # (`AshRpc.Manifest.Custom.custom_type?/1`), plus a NewType's subtype when the
  # fields came from it. The manifest module recompiles when one of them does.
  # Fields from manifest entries and built-ins need no dependency.
  # A declared type whose `typescript_type_alias/0` supplied the alias is one
  # too, and so is every NewType definition in `manifest.types`, so adding
  # `typescript_type_alias/0` to one later recompiles the manifest.
  @spec compile_dependencies(Manifest.t(), entries(), entries()) :: [module()]
  def compile_dependencies(%Manifest{types: types}, declared, builtin) do
    custom_type_dependencies =
      types
      |> Enum.filter(&AshRpc.Manifest.Custom.custom_type?/1)
      |> Enum.flat_map(fn %Manifest.Type{module: module} ->
        {_specs, dependencies} = resolve(module, declared, builtin)

        if alias_callback?(module, declared),
          do: [module | dependencies],
          else: dependencies
      end)

    new_types =
      for %Manifest.Type{module: module} <- types,
          is_atom(module) and not is_nil(module),
          new_type?(module),
          do: module

    Enum.uniq(custom_type_dependencies ++ new_types)
  end

  @doc """
  The hint for a map-like custom type with no declared fields: the ways to
  declare them, plus what to remove when the type exports
  `typescript_type/0` or a `scalar` entry covers it.
  """
  @spec hint(module(), entries(), entries()) :: String.t()
  def hint(module, declared, builtin) do
    removals =
      Enum.reject(
        [
          exports?(module, :typescript_type, 0) && "`typescript_type/0`",
          match?(%Scalar{}, entry(module, declared, builtin)) && "the `scalar` declaration"
        ],
        &(&1 == false)
      )

    case removals do
      [] ->
        @base_hint

      _ ->
        @base_hint <>
          " Remove #{Enum.join(removals, " and ")}: a map-like type's TypeScript is " <>
          "generated from its fields."
    end
  end

  @doc """
  The names of the aliased map-like type `module` (`t:names/0`): a declared
  custom type, or a field-bearing NewType that opts into an alias.
  `custom_types` is the persisted `t:custom_types/0`.

  The alias is `alias_name/3`'s. A library's schema name is `nil` when the
  entry the type's uses resolve to (`map_entry/2`) has a replacement for that
  library, else `:derive`. Raises `ArgumentError` for an invalid
  `typescript_type_alias/0` result (`check_alias_names/2` reports it first).
  """
  @spec names(module(), custom_types()) :: names()
  def names(module, %{declared: declared, builtin: builtin} = custom_types) do
    effective = map_entry(module, &entry(&1, declared, builtin))

    typescript =
      case alias_name(module, custom_types, true) do
        {:ok, name} -> name
        {:error, message} -> raise ArgumentError, message
      end

    %{
      typescript: typescript,
      zod: schema_name(effective, :zod),
      valibot: schema_name(effective, :valibot)
    }
  end

  @doc """
  The TypeScript alias of the map-like type `module` (a declared custom type
  or a field-bearing NewType), the first of:

    1. the `ts_alias` of its manifest `map` entry;
    2. the type's `typescript_type_alias/0`;
    3. a built-in `map` entry's `ts_alias` (`Money`);
    4. the joined module name (`SomeLib.Coordinates` → `SomeLibCoordinates`),
       when the type is aliased at all: `aliased_by_default?` (declared custom
       types), a manifest `map` entry for it (a field-less one opts a
       field-bearing NewType in), or `alias_all_types?`.

  `{:ok, nil}` when none applies. Like fields, the built-ins rank below the
  type's own callback. None of these is inherited, so a NewType over a
  declared type has its own.

  `{:error, message}`, naming the module, when `typescript_type_alias/0`
  decides the name and returns anything but a TypeScript identifier that
  isn't a reserved word.
  """
  @spec alias_name(module(), custom_types(), boolean()) ::
          {:ok, String.t() | nil} | {:error, String.t()}
  def alias_name(
        module,
        %{declared: declared, builtin: builtin} = custom_types,
        aliased_by_default?
      ) do
    entry = Map.get(declared, module)

    cond do
      match?(%MapType{ts_alias: name} when is_binary(name), entry) ->
        {:ok, entry.ts_alias}

      exports?(module, :typescript_type_alias, 0) ->
        callback_alias_name(module)

      match?(%MapType{ts_alias: name} when is_binary(name), builtin[module]) ->
        {:ok, builtin[module].ts_alias}

      aliased_by_default? or match?(%MapType{}, entry) or
          Map.get(custom_types, :alias_all_types?, false) ->
        {:ok, Codegen.Helpers.module_type_name(module)}

      true ->
        {:ok, nil}
    end
  end

  defp callback_alias_name(module) do
    case module.typescript_type_alias() do
      name when is_binary(name) ->
        subject = "The typescript_type_alias/0 result #{inspect(name)} of #{inspect(module)}"

        with :ok <- check_name(name, subject), do: {:ok, name}

      other ->
        {:error,
         "The typescript_type_alias/0 of #{inspect(module)} must return a string, " <>
           "got: #{inspect(other)}."}
    end
  end

  @doc false
  # The first alias error among the manifest's map-like definitions (declared
  # custom types and field-bearing NewTypes), as `{:error, message}`; `:ok`
  # when there is none. An error is an invalid `alias_name/3` result, or an
  # aliased field-bearing NewType that exports `typescript_type/0`
  # (through `typescript_type_alias/0` or `alias_all_types?`; a field-less
  # `map` entry on such a type is rejected by `NormalizeCustomTypes`).
  @spec check_alias_names(Manifest.t(), custom_types()) :: :ok | {:error, String.t()}
  def check_alias_names(%Manifest{types: types}, custom_types) do
    Enum.find_value(types, :ok, fn type ->
      cond do
        AshRpc.Manifest.Custom.custom_type?(type) ->
          alias_error(alias_name(type.module, custom_types, true))

        field_bearing_new_type?(type) ->
          case alias_name(type.module, custom_types, false) do
            {:ok, name} when is_binary(name) ->
              if exports?(type.module, :typescript_type, 0),
                do: {:error, type_callback_message(type.module)}

            result ->
              alias_error(result)
          end

        true ->
          nil
      end
    end)
  end

  defp alias_error({:error, _message} = error), do: error
  defp alias_error(_ok), do: nil

  # The callbacks' former names, and their current ones.
  @renamed_callbacks [
    typescript_type_name: :typescript_type,
    typescript_alias_name: :typescript_type_alias
  ]

  @doc false
  # The first type module the manifest reaches (a `manifest.types`
  # definition, or an `:unknown` node of `AshTypescript.Manifest.TypeUses`)
  # that exports a callback under its old name, as `{:error, message}`
  # naming the new one (both, for a module exporting both); `:ok` when there
  # is none. Entries for modules the manifest doesn't reach don't count.
  @spec check_renamed_callbacks(Manifest.t()) :: :ok | {:error, String.t()}
  def check_renamed_callbacks(%Manifest{types: types} = manifest) do
    unknown_modules =
      for %Manifest.Type{kind: :unknown, module: module} <-
            AshTypescript.Manifest.TypeUses.nodes(manifest),
          do: module

    (Enum.map(types, & &1.module) ++ unknown_modules)
    |> Enum.filter(&(is_atom(&1) and not is_nil(&1)))
    |> Enum.uniq()
    |> Enum.find_value(:ok, fn module ->
      case renamed_callback_messages(module) do
        [] -> nil
        messages -> {:error, Enum.join(messages, " ")}
      end
    end)
  end

  defp renamed_callback_messages(module) do
    for {old, new} <- @renamed_callbacks, exports?(module, old, 0) do
      "#{inspect(module)} exports `#{old}/0`, which is now `#{new}/0`: rename it."
    end
  end

  @doc false
  # The error for an aliased field-bearing NewType that exports
  # `typescript_type/0`.
  @spec type_callback_message(module()) :: String.t()
  def type_callback_message(module) do
    "#{inspect(module)} exports `typescript_type/0`: remove it; the alias is " <>
      "generated from the fields."
  end

  @doc false
  # `:ok` when `name` can be exported as a TypeScript type or const, else
  # `{:error, message}` starting with `subject` (`The ts_alias "x" of Mod`).
  @spec check_name(String.t(), String.t()) :: :ok | {:error, String.t()}
  def check_name(name, subject) do
    cond do
      not Regex.match?(@identifier, name) ->
        {:error, "#{subject} is not a TypeScript identifier."}

      name in @reserved_words ->
        {:error, "#{subject} is a TypeScript reserved word."}

      true ->
        :ok
    end
  end

  @doc false
  # How a message tells the user to rename a type's alias, and with it its
  # named schemas, by the kind of type: "rename it #{rename_hint(:map)}".
  # `:map` covers declared custom types and field-bearing NewTypes.
  @spec rename_hint(:map) :: String.t()
  def rename_hint(:map),
    do:
      "with `ts_alias \"…\"` on its `map` entry (or `typescript_type_alias/0` on the type, " <>
        "when no entry sets `ts_alias`)"

  @doc """
  The `map` entry a declared custom type's uses resolve to (`entry_of` maps a
  module to its entry, or `nil`): its own, else, for a NewType without an
  entry or `typescript_fields/0` of its own, its subtype's. `nil` when that
  entry is a `scalar` or a field-less `map` entry (which declares nothing),
  or there is none.
  """
  @spec map_entry(module(), (module() -> Scalar.t() | MapType.t() | nil)) :: MapType.t() | nil
  def map_entry(module, entry_of) do
    case entry_of.(module) do
      %MapType{fields: []} ->
        nil

      %MapType{} = entry ->
        entry

      nil ->
        if inherits_fields?(module),
          do: map_entry_only(entry_of.(Ash.Type.NewType.subtype_of(module)))

      _scalar ->
        nil
    end
  end

  defp map_entry_only(%MapType{fields: [_ | _]} = entry), do: entry
  defp map_entry_only(_), do: nil

  @field_bearing_kinds [:map, :keyword, :tuple, :struct]

  @doc false
  # A field-bearing NewType: an `Ash.Type.NewType` whose definition is
  # map-like (`:map`, `:keyword`, `:tuple` or `:struct`) with fields, and
  # not a declared custom type (`AshRpc.Manifest.Custom.custom_type?/1`).
  # Its fields come from the type, so its `map` entry has none.
  @spec field_bearing_new_type?(Manifest.Type.t()) :: boolean()
  def field_bearing_new_type?(%Manifest.Type{module: module, kind: kind} = definition)
      when kind in @field_bearing_kinds and is_atom(module) and not is_nil(module) do
    new_type?(module) and Manifest.Type.get_fields(definition) != [] and
      not AshRpc.Manifest.Custom.custom_type?(definition)
  end

  def field_bearing_new_type?(_definition), do: false

  @doc false
  # `field_bearing_new_type?/1` for a module, from its own definition
  # (`TypeResolver.resolve_definition/1`), so no manifest is needed. Compiles
  # the module first (`Code.ensure_compiled/1`); `false` for a module that
  # doesn't exist.
  @spec field_bearing_new_type_module?(module()) :: boolean()
  def field_bearing_new_type_module?(module) when is_atom(module) do
    match?({:module, _}, Code.ensure_compiled(module)) and new_type?(module) and
      field_bearing_new_type?(Manifest.Generator.TypeResolver.resolve_definition(module))
  end

  # `effective` is a `map` entry or `nil`.
  defp schema_name(effective, library) do
    if effective && Map.fetch!(effective, library), do: nil, else: :derive
  end

  # The callback names the type unless its entry's `ts_alias` does.
  defp alias_callback?(module, declared) do
    not match?(%MapType{ts_alias: name} when is_binary(name), Map.get(declared, module)) and
      exports?(module, :typescript_type_alias, 0)
  end

  defp inherits_fields?(module) do
    new_type?(module) and not exports?(module, :typescript_fields, 0) and
      Ash.Type.NewType.subtype_of(module) != module
  end

  @doc false
  # An entry's `key` mapping (`:ts_type`, `:zod` or `:valibot`) for a use
  # with `constraints`: the string as given, the MFA's result
  # (`apply(m, f, [constraints | a])`), or `nil` when the entry has none.
  # Raises `ArgumentError`, naming the option, the MFA and the module, when an
  # MFA returns anything but a string.
  @spec mapping(Scalar.t() | MapType.t(), :ts_type | :zod | :valibot, Keyword.t() | nil) ::
          String.t() | nil
  def mapping(entry, key, constraints) do
    case Map.get(entry, key) do
      {m, f, a} -> apply_mapping(entry, key, {m, f, a}, constraints || [])
      value -> value
    end
  end

  @doc false
  # A `scalar` entry's base type for a use, resolved to a manifest type: with
  # the entry's constraints, or with the use's for a member of a declared
  # custom type's definition (`custom_fields?`).
  @spec base_type(Scalar.t(), Keyword.t() | nil, boolean()) :: Manifest.Type.t()
  def base_type(%Scalar{} = entry, use_constraints, custom_fields?) do
    constraints = if custom_fields?, do: use_constraints || [], else: entry.constraints
    Manifest.Generator.TypeResolver.resolve(entry.type, constraints)
  end

  defp apply_mapping(entry, key, {m, f, a}, constraints) do
    case apply(m, f, [constraints | a]) do
      value when is_binary(value) ->
        value

      other ->
        raise ArgumentError,
              "the `#{key}` MFA #{Exception.format_mfa(m, f, length(a) + 1)} of the " <>
                "custom type #{inspect(entry.module)} must return a string, got: #{inspect(other)}"
    end
  end

  # ── precedence ───────────────────────────────────────────────────

  # {specs | nil, dependencies}
  defp resolve(module, declared, builtin) do
    {specs, dependencies} =
      case own(module, module, declared, builtin) do
        {:fields, specs, dependencies} -> {specs, dependencies}
        :scalar -> {nil, []}
        :none -> inherited(module, declared, builtin)
      end

    {merge_scalar_constraints(specs, declared, builtin), dependencies}
  end

  defp inherited(module, declared, builtin) do
    with true <- new_type?(module),
         subtype when subtype != module <- Ash.Type.NewType.subtype_of(module),
         {:fields, specs, dependencies} <- own(subtype, module, declared, builtin) do
      {specs, dependencies}
    else
      :scalar -> {nil, []}
      _ -> composite(module)
    end
  end

  # Steps 1-3 for `module`, named by `names_module`'s `typescript_field_names/0`
  # over `module`'s own.
  defp own(module, names_module, declared, builtin) do
    case Map.fetch(declared, module) do
      # A field-less entry declares no fields: the NewType's come from itself.
      {:ok, %MapType{fields: []}} ->
        :scalar

      {:ok, %MapType{fields: fields}} ->
        {:fields, Enum.map(fields, &field_spec(&1, &1.client_name)), []}

      {:ok, %Scalar{}} ->
        :scalar

      :error ->
        names = Map.merge(field_names(module), field_names(names_module))
        callback_or_builtin(module, names, builtin)
    end
  end

  defp callback_or_builtin(module, names, builtin) do
    cond do
      exports?(module, :typescript_fields, 0) ->
        {:fields, name_specs(module.typescript_fields(), names), [module]}

      match?(%MapType{}, Map.get(builtin, module)) ->
        %MapType{fields: fields} = Map.fetch!(builtin, module)
        {:fields, Enum.map(fields, &field_spec(&1, names[&1.name] || &1.client_name)), []}

      true ->
        :none
    end
  end

  defp composite(module) do
    with true <- ash_type?(module),
         constraints = default_constraints(module),
         true <- Ash.Type.composite?(module, constraints) do
      subtype = Ash.Type.NewType.subtype_of(module)
      names = Map.merge(field_names(subtype), field_names(module))

      specs =
        module |> Ash.Type.composite_types(constraints) |> Enum.map(&composite_spec(&1, names))

      {specs, Enum.uniq([module, subtype])}
    else
      _ -> {nil, []}
    end
  end

  defp default_constraints(module) do
    case Ash.Type.init(module, []) do
      {:ok, constraints} -> constraints
      _ -> []
    end
  end

  # ── specs ────────────────────────────────────────────────────────

  defp field_spec(%Field{} = field, client_name) do
    opts =
      [type: field.type, constraints: field.constraints || [], allow_nil?: field.allow_nil?]
      |> put_present(:description, field.description)
      |> put_present(:client_name, client_name)

    {field.name, opts}
  end

  # A malformed result is passed through, for ash_rpc's decoration to report.
  defp name_specs(specs, names) when is_list(specs), do: Enum.map(specs, &name_spec(&1, names))
  defp name_specs(other, _names), do: other

  defp name_spec({name, opts}, names) when is_list(opts),
    do: {name, put_present(opts, :client_name, names[name])}

  defp name_spec(other, _names), do: other

  # A field typed by a module with a `scalar` entry (declared, else built-in)
  # gets the entry's constraints under its own, as a DSL `map` field does
  # (`resolve_field_type/3`). Fields it doesn't change are left as declared.
  defp merge_scalar_constraints(specs, declared, builtin) when is_list(specs) do
    entry_of = &entry(&1, declared, builtin)

    Enum.map(specs, fn
      {name, opts} = spec when is_list(opts) ->
        with true <- Keyword.keyword?(opts),
             {:ok, type} <- Keyword.fetch(opts, :type),
             constraints = opts[:constraints] || [],
             {:ok, _base, merged} when merged != constraints <-
               resolve_field_type(type, constraints, entry_of) do
          {name, put_constraints(opts, merged)}
        else
          _ -> spec
        end

      spec ->
        spec
    end)
  end

  defp merge_scalar_constraints(specs, _declared, _builtin), do: specs

  @doc false
  # The type to check a field's constraints against, and the constraints it
  # carries: a module with a `scalar` entry (`entry_of.(module)`) resolves to
  # the entry's base type, with the entry's constraints merged under the
  # field's (`Keyword.merge/2`, the field winning per key; under `items:` for
  # an array). `:map` for a module with a `map` entry that has fields, and
  # `{:error, type}` for a module that is neither an entry nor an Ash type.
  # A field-less `map` entry counts as no entry, so the NewType itself checks
  # the field's constraints.
  @spec resolve_field_type(term(), keyword(), (term() -> Scalar.t() | MapType.t() | nil)) ::
          {:ok, term(), keyword()} | :map | {:error, term()}
  def resolve_field_type({:array, inner}, constraints, entry_of) do
    case resolve_field_type(inner, Keyword.get(constraints, :items, []), entry_of) do
      {:ok, base, []} -> {:ok, {:array, base}, constraints}
      {:ok, base, items} -> {:ok, {:array, base}, Keyword.put(constraints, :items, items)}
      other -> other
    end
  end

  def resolve_field_type(type, constraints, entry_of) do
    case entry_of.(type) do
      %Scalar{} = scalar -> {:ok, scalar.type, Keyword.merge(scalar.constraints, constraints)}
      %MapType{fields: [_ | _]} -> :map
      _none -> if Ash.Type.ash_type?(type), do: {:ok, type, constraints}, else: {:error, type}
    end
  end

  defp put_constraints(opts, constraints) do
    if Keyword.has_key?(opts, :constraints),
      do: Keyword.replace!(opts, :constraints, constraints),
      else: opts ++ [constraints: constraints]
  end

  defp composite_spec({name, _storage_key, type, constraints}, names),
    do: composite_spec({name, type, constraints}, names)

  defp composite_spec({name, type, constraints}, names),
    do:
      {name,
       put_present(
         [type: type, constraints: constraints, allow_nil?: false],
         :client_name,
         names[name]
       )}

  defp put_present(opts, _key, nil), do: opts
  defp put_present(opts, key, value), do: Keyword.delete(opts, key) ++ [{key, value}]

  # ── helpers ──────────────────────────────────────────────────────

  defp entry(module, declared, builtin),
    do: Map.get(declared, module) || Map.get(builtin, module)

  defp field_names(module), do: Helpers.typescript_field_names(module)

  defp exports?(module, function, arity),
    do: Code.ensure_loaded?(module) and function_exported?(module, function, arity)

  defp ash_type?(module), do: Code.ensure_loaded?(module) and Ash.Type.ash_type?(module)

  defp new_type?(module), do: ash_type?(module) and Ash.Type.NewType.new_type?(module)
end
