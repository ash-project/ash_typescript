# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.NameValidation do
  @moduledoc """
  The rules for the names codegen emits, and the predicates they use.

  The rules are pure functions of one name and its context: they take plain
  values (atoms, strings, booleans), never a manifest, a resource, a DSL
  struct or a formatter. Each returns `:ok` or `{:error, reason}`, with the
  first reason that applies:

    * `check_client_name/3`: a client name (a key of a generated object);
    * `check_binding_name/2`: a generated function, const, type or schema
      name;
    * `check_raw_binding_name/1`: the raw `rpc_action`, `typed_query` or route
      name;
    * `check_alias_name/2`: a static type alias.

  Where each name sits in the manifest, and how a problem is reported, is
  `AshTypescript.Manifest.NameCheck`'s, which applies `check_client_name/3`
  to every client name, `check_binding_name/2` and
  `check_raw_binding_name/1` to every binding name, and `check_alias_name/2`
  to every static type alias, when the manifest compiles.

  The predicates:

    * `identifier?/1`: the name can be written as is as a TypeScript property
      name or identifier;
    * `invalid_name?/1`: the name has an underscore before a digit (`field_1`,
      whose formatted `field1` doesn't tell it from `field1`) or a `?`;
    * `reserved_word?/1`: TypeScript can't bind the name as a function or const
      in a generated ES module;
    * `type_keyword?/1`: the name is a predefined TypeScript type name, which
      can't name a type alias;
    * `make_name_better/1`: the rename suggestion shown in error messages,
      and `suggest_name/1`, which also turns other non-identifier characters
      into underscores.
  """

  @type reason ::
          :not_identifier
          | :digit_after_underscore
          | :reserved_word
          | :type_keyword
          | :invalid_raw_name
          | {:alias, String.t()}

  # The JavaScript reserved words, strict mode included (generated files are
  # ES modules), and the names strict mode can't bind (`eval`, `arguments`).
  @js_reserved_words ~w(
    break case catch class const continue debugger default delete do else enum
    export extends false finally for function if import in instanceof new null
    return super switch this throw true try typeof var void while with
    implements interface let package private protected public static yield
    await eval arguments
  )

  # The predefined type names TypeScript can't use as a type alias name.
  @ts_type_keywords ~w(any unknown never object string number boolean bigint symbol undefined)

  @doc """
  Checks a client name (a key of a generated object). `explicit?` is true when
  a mapping, callback or `client_name` set it, false when the formatter made
  it from `raw`.

  `{:error, :not_identifier}` unless `client` is an identifier (`identifier?/1`),
  then `{:error, :digit_after_underscore}` for a formatter-made name whose
  `raw` has an underscore before a digit. An explicit name is only checked
  for validity.
  """
  @spec check_client_name(atom(), String.t(), boolean()) ::
          :ok | {:error, :not_identifier | :digit_after_underscore}
  def check_client_name(raw, client, explicit?) do
    cond do
      not identifier?(client) ->
        {:error, :not_identifier}

      not explicit? and Regex.match?(~r/_+\d/, to_string(raw)) ->
        {:error, :digit_after_underscore}

      true ->
        :ok
    end
  end

  @doc """
  Checks a generated function, const, type, schema or key name by how it is
  bound (`role`):

    * `:value`, an exported function or const: an identifier
      (`{:error, :not_identifier}`) that isn't a JavaScript reserved word
      (`{:error, :reserved_word}`);
    * `:type`, an exported type: also not a predefined TypeScript type name
      (`string`, `any`, …: `{:error, :type_keyword}`);
    * `:key`, an unquoted key of a generated type: only an identifier.
  """
  @spec check_binding_name(String.t(), :value | :type | :key) ::
          :ok | {:error, :not_identifier | :reserved_word | :type_keyword}
  def check_binding_name(name, role) when role in [:value, :type, :key] do
    cond do
      not identifier?(name) -> {:error, :not_identifier}
      role == :key -> :ok
      reserved_word?(name) -> {:error, :reserved_word}
      role == :type and type_keyword?(name) -> {:error, :type_keyword}
      true -> :ok
    end
  end

  @doc """
  Checks the raw `rpc_action`, `typed_query` or route name: `{:error,
  :invalid_raw_name}` when it has a `?` or an underscore before a digit
  (`invalid_name?/1`).
  """
  @spec check_raw_binding_name(atom()) :: :ok | {:error, :invalid_raw_name}
  def check_raw_binding_name(raw) do
    if invalid_name?(raw), do: {:error, :invalid_raw_name}, else: :ok
  end

  @doc """
  Checks a static type alias with `CustomTypes.check_name/2`;
  `subject` (`The ts_alias "x" of Mod`) starts its message.
  """
  @spec check_alias_name(String.t(), String.t()) :: :ok | {:error, {:alias, String.t()}}
  def check_alias_name(name, subject) do
    case AshTypescript.CustomTypes.check_name(name, subject) do
      :ok -> :ok
      {:error, message} -> {:error, {:alias, message}}
    end
  end

  @doc """
  Returns `true` when `name` (atom or string) would produce an awkward
  TypeScript identifier and should be remapped via `field_names` /
  `argument_names` / `metadata_field_names`.
  """
  def invalid_name?(name) do
    Regex.match?(~r/_+\d|\?/, to_string(name))
  end

  @doc """
  Returns `true` when `name` (atom or string) can be written as-is as a
  TypeScript property name / identifier (`[A-Za-z_$][A-Za-z0-9_$]*`).

  Catches what `invalid_name?/1` doesn't — names like `:"foo-bar"`, `:"1st"` or
  `:"with space"`, which would otherwise be emitted as unquoted keys.
  """
  def identifier?(name) do
    Regex.match?(~r/\A[A-Za-z_$][A-Za-z0-9_$]*\z/, to_string(name))
  end

  @doc """
  Returns the suggested replacement name for use in error messages. Does not
  apply the configured client formatter — callers should call this only to
  show the user what to put in their `field_names` mapping.
  """
  def make_name_better(name) do
    name
    |> to_string()
    |> String.replace(~r/_+\d/, fn v -> String.trim_leading(v, "_") end)
    |> String.replace("?", "")
  end

  @doc """
  Returns `true` when `name` can be a key of a resource's `field_names`: a
  name that can't be used as is, because it has a `?` or an underscore before
  a digit (`invalid_name?/1`) or isn't an identifier (`identifier?/1`). Any
  other name needs no mapping.
  """
  @spec field_names_key?(atom() | String.t()) :: boolean()
  def field_names_key?(name), do: invalid_name?(name) or not identifier?(name)

  @doc """
  Returns an identifier to suggest in place of `name`: `make_name_better/1`'s
  result, with every other run of characters an identifier can't hold turned
  into an underscore, and an underscore before a leading digit
  (`:"due-at"` → `"due_at"`, `:"1st"` → `"_1st"`).
  """
  @spec suggest_name(atom() | String.t()) :: String.t()
  def suggest_name(name) do
    better =
      name
      |> make_name_better()
      |> String.replace(~r/[^A-Za-z0-9_$]+/, "_")

    if Regex.match?(~r/\A\d/, better), do: "_" <> better, else: better
  end

  @doc """
  Returns `true` when `name` (atom or string) is a JavaScript reserved word,
  which a generated ES module can't use as a function or const name.
  TypeScript type keywords (`string`, `number`, …) are not reserved here.
  """
  def reserved_word?(name), do: to_string(name) in @js_reserved_words

  @doc """
  Returns `true` when `name` (atom or string) is a predefined TypeScript type
  name (`string`, `any`, `never`, …), which a type alias can't be named
  (`Type alias name cannot be 'string'`).
  """
  def type_keyword?(name), do: to_string(name) in @ts_type_keywords

  @doc false
  # The words `reserved_word?/1` rejects, for checks that extend the set.
  def js_reserved_words, do: @js_reserved_words

  @doc false
  # The words `type_keyword?/1` rejects, for checks that extend the set.
  def ts_type_keywords, do: @ts_type_keywords
end
