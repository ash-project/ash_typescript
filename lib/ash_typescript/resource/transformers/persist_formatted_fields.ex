# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Resource.Transformers.PersistFormattedFields do
  @moduledoc false

  use Spark.Dsl.Transformer

  @builtin_formatters [:camel_case, :snake_case, :pascal_case]

  def after?(_), do: true

  def transform(dsl_state) do
    fields = collect_public_field_atoms(dsl_state)
    overrides = Spark.Dsl.Transformer.get_option(dsl_state, [:typescript], :field_names, [])

    pairs = for field <- fields, formatter <- @builtin_formatters, do: {field, formatter}

    persisted =
      Enum.reduce(pairs, dsl_state, fn {field, formatter}, acc ->
        Spark.Dsl.Transformer.persist(
          acc,
          {:typescript_formatted_fields, field, formatter},
          formatted_name(field, formatter, overrides)
        )
      end)

    {:ok, persisted}
  end

  defp formatted_name(field, formatter, overrides) do
    case Keyword.fetch(overrides, field) do
      {:ok, override} when is_binary(override) -> override
      _ -> AshTypescript.FieldFormatter.compute_field_name(field, formatter)
    end
  end

  defp collect_public_field_atoms(dsl_state) do
    [
      Ash.Resource.Info.public_attributes(dsl_state),
      Ash.Resource.Info.public_relationships(dsl_state),
      Ash.Resource.Info.public_calculations(dsl_state),
      Ash.Resource.Info.public_aggregates(dsl_state)
    ]
    |> Enum.concat()
    |> Enum.map(& &1.name)
    |> Enum.uniq()
  end
end
