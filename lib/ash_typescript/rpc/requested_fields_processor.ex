# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.RequestedFieldsProcessor do
  @moduledoc """
  Processes requested fields for Ash resources, determining which fields should be selected
  vs loaded, and building extraction templates for result processing.

  This module handles different action types:
  - CRUD actions (:read, :create, :update, :destroy) return resource records
  - Generic actions (:action) return arbitrary types as specified in their `returns` field

  ## Architecture

  This module serves as the main entry point and delegates to `FieldSelector`,
  which uses a unified type-driven recursive dispatch pattern (similar to `ValueFormatter`).

  The key insight is that each type is self-describing via `{type, constraints}`,
  so no separate classification step is needed.
  """

  alias AshTypescript.Rpc.FieldProcessing.{Atomizer, FieldSelector}

  @doc """
  Atomizes requested fields by converting standalone strings to atoms and map keys to atoms.

  Uses the configured input field formatter to properly parse field names from client format
  to internal format before converting to atoms.

  When a resource is provided, field_names DSL mappings are checked first to handle
  custom client→internal field name mappings.

  ## Parameters

  - `requested_fields` - List of strings/atoms or maps for relationships
  - `resource` - Optional resource module for field_names DSL lookup

  ## Examples

      iex> atomize_requested_fields(["id", "title", %{"user" => ["id", "name"]}])
      [:id, :title, %{user: [:id, :name]}]

      iex> atomize_requested_fields([%{"self" => %{"args" => %{"prefix" => "test"}}}])
      [%{self: %{args: %{prefix: "test"}}}]
  """
  defdelegate atomize_requested_fields(requested_fields, resource \\ nil), to: Atomizer

  @doc """
  Processes requested fields for a given resource and action.

  Returns `{:ok, {select_fields, load_fields, extraction_template}}` or `{:error, error}`.

  ## Parameters

  - `resource` - The Ash resource module
  - `action` - The action name (atom)
  - `requested_fields` - List of field atoms or maps for relationships

  ## Examples

      iex> process(MyApp.Todo, :read, [:id, :title, %{user: [:id, :name]}])
      {:ok, {[:id, :title], [{:user, [:id, :name]}], [:id, :title, [user: [:id, :name]]]}}

      iex> process(MyApp.Todo, :read, [%{user: [:invalid_field]}])
      {:error, %{type: :invalid_field, field: "user.invalidField"}}
  """
  defdelegate process(resource, action_name, requested_fields), to: FieldSelector
end
