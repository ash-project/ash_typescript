# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.FieldProcessing.Utilities do
  @moduledoc """
  Utility functions for field processing, including load spec building,
  field path formatting, and template formatting.
  """

  @doc """
  Builds a load specification for Ash, combining select and load fields.

  ## Examples

      iex> build_load_spec(:user, [:id, :name], [:posts])
      {:user, [:id, :name, :posts]}

      iex> build_load_spec(:user, [:id, :name], [])
      {:user, [:id, :name]}
  """
  def build_load_spec(field_name, nested_select, nested_load) do
    load_fields =
      case nested_load do
        [] -> nested_select
        _ -> nested_select ++ nested_load
      end

    {field_name, load_fields}
  end

  @doc """
  Builds a formatted field path for error messages.

  Uses the configured output field formatter to format field names
  for client-facing error messages.

  ## Examples

      iex> build_field_path([], :user)
      "user"

      iex> build_field_path([:posts], :title)
      "posts.title"

      iex> build_field_path([:user, :posts], :title)
      "user.posts.title"
  """
  def build_field_path(path, field_name) do
    all_parts = path ++ [field_name]
    formatter = AshTypescript.Rpc.output_field_formatter()

    case all_parts do
      [single] ->
        AshTypescript.FieldFormatter.format_field(single, formatter)

      [first | rest] ->
        formatted_first = AshTypescript.FieldFormatter.format_field(first, formatter)

        "#{formatted_first}.#{Enum.map_join(rest, ".", fn field -> AshTypescript.FieldFormatter.format_field(field, formatter) end)}"
    end
  end

  @doc """
  Formats an extraction template, separating standalone atoms from keyword pairs.

  This ensures the template format is consistent for the result processor.

  ## Examples

      iex> format_extraction_template([:id, :title, {:user, [:id, :name]}])
      [:id, :title, {:user, [:id, :name]}]
  """
  def format_extraction_template(template) do
    {atoms, keyword_pairs} =
      Enum.reduce(template, {[], []}, fn item, {atoms, kw_pairs} ->
        case item do
          # Tuple types store the index only
          {key, value} when is_atom(key) and is_map(value) ->
            {atoms, kw_pairs ++ [{key, value}]}

          {key, value} when is_atom(key) ->
            {atoms, kw_pairs ++ [{key, format_extraction_template(value)}]}

          atom when is_atom(atom) ->
            {atoms ++ [atom], kw_pairs}

          other ->
            {atoms ++ [other], kw_pairs}
        end
      end)

    atoms ++ keyword_pairs
  end

  @doc """
  Extracts the embedded resource type from an array or direct type.

  ## Examples

      iex> extract_embedded_resource_type({:array, MyApp.Address})
      MyApp.Address

      iex> extract_embedded_resource_type(MyApp.Address)
      MyApp.Address
  """
  def extract_embedded_resource_type({:array, embedded_resource}), do: embedded_resource
  def extract_embedded_resource_type(embedded_resource), do: embedded_resource
end
