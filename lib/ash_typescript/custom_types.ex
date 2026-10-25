# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.CustomTypes do
  @moduledoc """
  The fields a custom `use Ash.Type` module declares, as the field specs
  `AshRpc.Manifest.Decorator.decorate/3` takes (`custom_type_fields:`).

  `fields_for/3` checks, in order:

    1. the manifest module's `custom_types` entry for the module: a `map`
       entry's fields (with their `client_name`), or `nil` for a `scalar`;
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

  `AshTypescript.Manifest.Transformers.DecorateManifest` passes the manifest's
  entries and the built-ins; `AshTypescript.RpcMappingSource` passes only the
  built-ins.
  """

  alias Ash.Info.Manifest
  alias AshTypescript.CustomTypes.{Builtin, Field, MapType, Scalar}
  alias AshTypescript.Helpers

  @type entries :: %{module() => Scalar.t() | MapType.t()}
  @type fields_fun :: (module() -> [AshRpc.MappingSource.field_spec()] | nil)

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

  @doc """
  The `custom_type_fields:` closure over persisted `custom_types`
  (`%{declared: …, builtin: …}`), or over the built-ins alone for `nil`.
  """
  @spec fields_fun(%{declared: entries(), builtin: entries()} | nil) :: fields_fun()
  def fields_fun(%{declared: declared, builtin: builtin}), do: &fields_for(&1, declared, builtin)
  def fields_fun(nil), do: fields_fun(%{declared: %{}, builtin: Builtin.by_module()})

  @doc """
  The type modules whose `typescript_fields/0` or `composite_types/1`
  supplied the fields of a declared custom type in `manifest.types`
  (`AshRpc.Manifest.Custom.custom_type?/1`), plus a NewType's subtype when the
  fields came from it. The manifest module recompiles when one of them does.
  Fields from manifest entries and built-ins need no dependency.
  """
  @spec compile_dependencies(Manifest.t(), entries(), entries()) :: [module()]
  def compile_dependencies(%Manifest{types: types}, declared, builtin) do
    types
    |> Enum.filter(&AshRpc.Manifest.Custom.custom_type?/1)
    |> Enum.flat_map(fn %Manifest.Type{module: module} ->
      {_specs, dependencies} = resolve(module, declared, builtin)
      dependencies
    end)
    |> Enum.uniq()
  end

  @doc """
  The hint for a map-like custom type with no declared fields: the ways to
  declare them, plus what to remove when the type exports
  `typescript_type_name/0` or a `scalar` entry covers it.
  """
  @spec hint(module(), entries(), entries()) :: String.t()
  def hint(module, declared, builtin) do
    removals =
      Enum.reject(
        [
          exports?(module, :typescript_type_name, 0) && "`typescript_type_name/0`",
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
  An entry's `key` mapping (`:typescript`, `:zod` or `:valibot`) for a use
  with `constraints`: the string as given, the MFA's result
  (`apply(m, f, [constraints | a])`), or `nil` when the entry has none.
  Raises `ArgumentError`, naming the option, the MFA and the module, when an
  MFA returns anything but a string.
  """
  @spec mapping(Scalar.t() | MapType.t(), :typescript | :zod | :valibot, Keyword.t() | nil) ::
          String.t() | nil
  def mapping(entry, key, constraints) do
    case Map.get(entry, key) do
      {m, f, a} -> apply_mapping(entry, key, {m, f, a}, constraints || [])
      value -> value
    end
  end

  @doc """
  A `scalar` entry's base type for a use, resolved to a manifest type: with
  the entry's constraints, or with the use's for a member of a declared
  custom type's definition (`custom_fields?`, Decision 36).
  """
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
    case own(module, module, declared, builtin) do
      {:fields, specs, dependencies} -> {specs, dependencies}
      :scalar -> {nil, []}
      :none -> inherited(module, declared, builtin)
    end
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
        specs = Enum.map(module.typescript_fields(), &name_spec(&1, names))
        {:fields, specs, [module]}

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

  defp name_spec({name, opts}, names), do: {name, put_present(opts, :client_name, names[name])}

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
