# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.ScalarAliases do
  @moduledoc """
  The TypeScript alias names of scalars: scalar custom types (a `kind:
  :unknown` use of a `use Ash.Type` module, with a `scalar` entry or
  `typescript_type/0`) and NewTypes over primitives (a definition whose kind
  the kind table maps, such as `:string` or `:integer`; not enums, arrays,
  unions, containers or resources, and not a NewType over a scalar custom
  type).

  `name/2` takes the node `TypeMapper` maps the scalar from (the `:unknown`
  use, or the NewType's definition) and returns the first of:

    1. the `ts_alias` of the module's manifest `scalar` entry: a string, or an
       MFA called with the node's constraints, whose `nil` keeps that use
       inline with no fallback;
    2. the type's `typescript_type_alias/0`;
    3. the `ts_alias` of a built-in `scalar` entry
       (`AshTypescript.CustomTypes.Builtin`: ULID, Ltree), with the same rule,
       when the manifest has no `scalar` entry for the module (a manifest
       entry replaces the built-in whole);

  else `nil`. A scalar's alias body is its TypeScript by the existing
  precedence (entry `ts_type`, `typescript_type/0`, built-in, base type), so
  `typescript_type/0` combines with any alias opt-in. A name applies at every
  position that renders the scalar (`TypeMapper` renders the name); zod and
  valibot schemas stay inline.

  `aliases/1` and `alias_lines/1` collect the names used under the alias-walk
  roots (`AshTypescript.Codegen.TypeAliases.roots/4`) with their bodies, one
  alias per distinct name, for the primitive alias block of the types file.
  """

  alias Ash.Info.Manifest.Type
  alias AshTypescript.Codegen.TypeMapper
  alias AshTypescript.CustomTypes
  alias AshTypescript.CustomTypes.Scalar
  alias AshTypescript.Manifest.Custom
  alias AshTypescript.Manifest.Verifiers.VerifyCustomTypeNames
  alias AshTypescript.TypeSystem.Introspection

  @doc """
  The aliases of the scalars used under `roots` (`%Ash.Info.Manifest.Type{}`
  nodes), as `{name, body, module}` sorted by name, one per distinct name;
  `module` is a type the name belongs to. Each body is the scalar's
  TypeScript (`TypeMapper.expand_scalar/2`) at its use: a member of a
  declared custom type's definition maps with its own constraints. Throws
  `{:error, message}` when one name has two bodies (an MFA `ts_alias` giving
  one name to different `ts_type`s, or one name on scalars that render
  differently). Reads the configured manifest (`AshTypescript.with_manifest/2`
  applies).
  """
  @spec aliases([Type.t()]) :: [{String.t(), String.t(), module()}]
  def aliases(roots) do
    custom_types = Custom.custom_types(nil)

    {found, _seen} =
      Enum.reduce(roots, {[], MapSet.new()}, &walk(&1, false, custom_types, &2))

    found
    |> Enum.uniq()
    |> Enum.group_by(&elem(&1, 0), &Tuple.delete_at(&1, 0))
    |> Enum.map(&one_body!/1)
    |> Enum.sort()
  end

  @doc "The `export type <name> = <body>;` lines of `aliases/1`."
  @spec alias_lines([Type.t()]) :: [String.t()]
  def alias_lines(roots),
    do: Enum.map(aliases(roots), fn {name, body, _module} -> "export type #{name} = #{body};" end)

  # `custom_fields?` as in `TypeMapper`: true for a member of a declared
  # custom type's definition; arrays keep it, nested containers set their
  # own. Named types are walked once, by module.
  defp walk(%Type{kind: :array, item_type: item_type}, custom_fields?, custom_types, acc),
    do: walk(item_type, custom_fields?, custom_types, acc)

  defp walk(%Type{kind: :union, members: members}, _custom_fields?, custom_types, acc),
    do: Enum.reduce(members || [], acc, &walk(&1.type, false, custom_types, &2))

  defp walk(%Type{kind: kind} = type, _custom_fields?, custom_types, acc)
       when kind in [:map, :keyword, :struct, :tuple] do
    custom_fields? = AshRpc.Manifest.Custom.custom_type?(type)

    type
    |> Type.get_fields()
    |> Enum.reduce(acc, &walk(&1.type, custom_fields?, custom_types, &2))
  end

  defp walk(%Type{kind: :type_ref, module: module}, _custom_fields?, custom_types, {found, seen})
       when is_atom(module) and not is_nil(module) do
    if MapSet.member?(seen, module) do
      {found, seen}
    else
      module
      |> Introspection.named_type_definition()
      |> walk(false, custom_types, {found, MapSet.put(seen, module)})
    end
  end

  defp walk(%Type{} = node, custom_fields?, custom_types, {found, seen}) do
    case name(node, custom_types) do
      nil ->
        {found, seen}

      name ->
        body = TypeMapper.expand_scalar(node, direction: :output, custom_fields?: custom_fields?)
        {[{name, body, node.module} | found], seen}
    end
  end

  defp walk(_node, _custom_fields?, _custom_types, acc), do: acc

  defp one_body!({name, uses}) do
    case uses |> Enum.map(&elem(&1, 0)) |> Enum.uniq() do
      [body] ->
        {name, body, uses |> Enum.map(&elem(&1, 1)) |> Enum.min()}

      bodies ->
        lines =
          bodies
          |> Enum.sort()
          |> Enum.map_join("\n", fn body ->
            modules =
              for {^body, module} <- uses, uniq: true, do: inspect(module)

            "  - `#{body}` (#{modules |> Enum.sort() |> Enum.join(", ")})"
          end)

        throw(
          {:error,
           """
           The TypeScript alias `#{name}` of a scalar has more than one body:
           #{lines}

           An alias names one TypeScript type: give each its own name (an MFA \
           `ts_alias` that returns a name per `ts_type`), or `nil` to keep a use inline.
           """}
        )
    end
  end

  @doc """
  The alias name of the scalar `node` (see the module doc), or `nil`.
  `custom_types` is the persisted `t:AshTypescript.CustomTypes.custom_types/0`.
  Raises `ArgumentError` for an invalid `typescript_type_alias/0` result
  (`AshTypescript.CustomTypes.check_alias_names/2` reports it at compile
  time) or an MFA `ts_alias` result that isn't a string or `nil`. Throws
  `{:error, message}`, naming the module, the MFA and the result, for an MFA
  result that can't be exported: not a TypeScript identifier, a reserved
  word or a global the generated code uses (`CustomTypes.check_name/2`), a
  name ash_typescript generates (`UUID`, `InferResult`, …), or the entry's
  `ts_type` at that use. Every use and the alias block go through here, so
  they agree.
  """
  @spec name(Type.t(), CustomTypes.custom_types()) :: String.t() | nil
  def name(%Type{module: module} = node, custom_types) do
    case source(node, custom_types) do
      nil ->
        nil

      {:entry, %Scalar{ts_alias: {m, f, a}} = entry} ->
        entry
        |> CustomTypes.mapping(:ts_alias, node.constraints)
        |> check_mfa_name!(entry, node, {m, f, a})

      {:entry, entry} ->
        CustomTypes.mapping(entry, :ts_alias, node.constraints)

      :callback ->
        case CustomTypes.callback_alias_name(module) do
          {:ok, name} -> name
          {:error, message} -> raise ArgumentError, message
        end
    end
  end

  # An MFA `ts_alias`'s result for `node` must be exportable (a TypeScript
  # identifier, not a reserved word or a global the generated code uses,
  # `CustomTypes.check_name/2`), not a fixed generated name
  # (`VerifyCustomTypeNames.reserved_names/0`), and not the use's own body
  # (the entry's `ts_type`, an MFA too, at the use's constraints). The
  # compile-time checks never see these names, so codegen throws
  # `{:error, message}`.
  defp check_mfa_name!(nil, _entry, _node, _mfa), do: nil

  defp check_mfa_name!(name, entry, %Type{module: module} = node, {m, f, a}) do
    subject =
      "The result #{inspect(name)} of the `ts_alias` MFA " <>
        "#{Exception.format_mfa(m, f, length(a) + 1)} of the custom type #{inspect(module)}"

    with :ok <- CustomTypes.check_name(name, subject),
         :ok <- check_not_reserved(name, subject),
         :ok <- check_not_own_body(name, entry, node, subject) do
      name
    else
      {:error, message} -> throw({:error, message})
    end
  end

  defp check_not_reserved(name, subject) do
    if name in VerifyCustomTypeNames.reserved_names(),
      do: {:error, "#{subject} is a type ash_typescript generates: return another name."},
      else: :ok
  end

  defp check_not_own_body(name, entry, node, subject) do
    if CustomTypes.mapping(entry, :ts_type, node.constraints) == name do
      {:error,
       "#{subject} is its ts_type at that use, so the alias would alias itself " <>
         "(`export type #{name} = #{name};`): return another name, or nil to keep the " <>
         "use inline."}
    else
      :ok
    end
  end

  @doc false
  # What names the scalar `node`: `{:entry, entry}` (its `ts_alias`),
  # `:callback`, or `nil` when it isn't aliased (or isn't a scalar). Lets
  # compile-time checks tell the sources apart without calling an MFA.
  @spec source(Type.t(), CustomTypes.custom_types()) ::
          {:entry, Scalar.t()} | :callback | nil
  def source(%Type{module: module} = node, %{declared: declared, builtin: builtin}) do
    if scalar_node?(node) do
      declared = scalar_entry(Map.get(declared, module))
      builtin = scalar_entry(Map.get(builtin, module))

      cond do
        declared && declared.ts_alias -> {:entry, declared}
        exports?(module, :typescript_type_alias, 0) -> :callback
        # A manifest entry replaces the built-in whole.
        declared -> nil
        builtin && builtin.ts_alias -> {:entry, builtin}
        true -> nil
      end
    end
  end

  # A `kind: :unknown` node of a module that isn't a NewType, or a NewType's
  # definition with a primitive kind. Modules of the primitive table
  # (`Ash.Type.UtcDatetime`, …) map before any entry and are never aliased.
  defp scalar_node?(%Type{module: module, kind: kind})
       when is_atom(module) and not is_nil(module) do
    cond do
      TypeMapper.primitive_module?(module) -> false
      kind == :unknown -> not new_type?(module)
      TypeMapper.primitive_kind?(kind) -> new_type?(module)
      true -> false
    end
  end

  defp scalar_node?(_node), do: false

  defp scalar_entry(%Scalar{} = entry), do: entry
  defp scalar_entry(_other), do: nil

  defp new_type?(module),
    do: Code.ensure_loaded?(module) and Ash.Type.NewType.new_type?(module)

  defp exports?(module, function, arity),
    do: Code.ensure_loaded?(module) and function_exported?(module, function, arity)
end
