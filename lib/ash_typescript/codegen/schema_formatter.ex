# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Codegen.SchemaFormatter do
  @moduledoc """
  Behaviour defining the output-format interface for schema generators.

  Implement this behaviour to add a new validation library target (e.g. Zod, Valibot).
  `AshTypescript.Codegen.SchemaCore` handles all resource introspection, topological
  sorting, and structural generation; implementations only provide the output syntax.

  ## Implementing a new formatter

      defmodule MyLib.SchemaFormatter do
        @behaviour AshTypescript.Codegen.SchemaFormatter

        def null_schema, do: "ml.null()"
        def any_schema, do: "ml.any()"
        # ...
      end
  """

  @doc "Schema for nil / null type"
  @callback null_schema() :: String.t()

  @doc "Fallback schema for unknown/any type"
  @callback any_schema() :: String.t()

  @doc "Fallback for custom Ash types that carry a `typescript_type_name`"
  @callback custom_type_fallback() :: String.t()

  @doc "Map of aggregate kind atoms to their schema strings (e.g. `%{count: \"z.number().int()\"}`)."
  @callback aggregate_types() :: %{atom() => String.t()}

  @doc "Map of simple Ash type modules to schema strings — no constraint handling needed."
  @callback simple_primitives() :: %{module() => String.t()}

  @doc "Map of atom-symbol primitives (e.g. `:map`) to schema strings."
  @callback atom_primitives() :: %{atom() => String.t()}

  @doc "Map of third-party Ash type modules (e.g. `AshMoney.Types.Money`) to schema strings."
  @callback third_party_types() :: %{module() => String.t()}

  @doc "Wrap an inner schema string in an array type."
  @callback wrap_array(inner :: String.t()) :: String.t()

  @doc """
  Wrap a schema string as omittable — i.e. the field may be absent from the
  input object. In zod this is `.optional()`; in valibot, `v.optional(...)`.
  Both libraries' optional accepts `undefined` only — not `null`. To accept
  `null`, compose with `wrap_nullable/1`.
  """
  @callback wrap_optional(schema :: String.t()) :: String.t()

  @doc """
  Wrap a schema string as nullable — i.e. the field's value may be `null`.
  In zod this is `.nullable()`; in valibot, `v.nullable(...)`.

  For fields that may be both omitted *and* null (the common case for nullable
  Ash attributes — `JSON.stringify` drops `undefined` keys, so clearing a
  nullable attribute requires sending `"field": null`), compose with
  `wrap_optional/1`. Convention: apply `wrap_nullable` first (innermost), then
  `wrap_optional`. The result is equivalent to zod's `.nullish()` shorthand.
  """
  @callback wrap_nullable(schema :: String.t()) :: String.t()

  @doc "Wrap a comma-joined set of `key: schema` fields in an inline object schema."
  @callback wrap_object(fields :: String.t()) :: String.t()

  @doc "Wrap a comma-joined set of schema strings in a union type."
  @callback wrap_union(schemas :: String.t()) :: String.t()

  @doc "Record/map schema — string keys, any values."
  @callback wrap_record() :: String.t()

  @doc "Enum schema from a comma-joined string of quoted values."
  @callback format_enum(values :: String.t()) :: String.t()

  @doc """
  Build a string schema, applying `constraints` if present.
  `require_non_empty` is true when the field is non-nullable — callers should
  enforce a minimum length of 1 when no explicit `:min_length` constraint exists.
  """
  @callback format_string(constraints :: keyword(), require_non_empty :: boolean()) :: String.t()

  @doc "Build an integer schema, applying min/max constraints if present."
  @callback format_integer(constraints :: keyword()) :: String.t()

  @doc "Build a float schema, applying min/max/gt/lt constraints if present."
  @callback format_float(constraints :: keyword()) :: String.t()

  @doc "Ltree type represented as an array of strings."
  @callback ltree_array() :: String.t()

  @doc "Ltree type represented as a string-or-array-of-strings union."
  @callback ltree_union() :: String.t()

  @doc ~S'The schema variable name suffix (e.g. `"Schema"` or `"ValibotSchema"`).'
  @callback schema_suffix() :: String.t()

  @doc "Whether schema generation is enabled in the current project config."
  @callback generate_schemas_enabled?() :: boolean()

  @doc "Human-readable label for the resource schemas section comment header."
  @callback section_header() :: String.t()

  @doc ~S'The library namespace prefix used when building schema declarations ("z" or "v").'
  @callback library_prefix() :: String.t()

  @doc ~S'The TypeScript import statement for the validation library (e.g. `import { z } from "zod"`).'
  @callback import_statement(import_path :: String.t()) :: String.t()

  @doc ~S'Human-readable library name for comments and error messages (e.g. "Zod" or "Valibot").'
  @callback library_name() :: String.t()

  @doc "The import path for the validation library from application config."
  @callback configured_import_path() :: String.t()
end
