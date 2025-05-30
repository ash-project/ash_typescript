defmodule Mix.Tasks.AshTypescript.Codegen do
  @moduledoc """
  Generates TypeScript types for Ash RPC-calls.

  Usage:
    mix ash_typescript.codegen --files "assets/js/ash_rpc/*.json, assets/list_users.json" --output "assets/js/ash_generated.ts"
  """

  @shortdoc "Generates TypeScript types for Ash RPC-calls"

  use Mix.Task
  alias AshTypescript.Helpers

  def run(args) do
    Mix.Task.run("compile")

    {opts, _remaining, _invalid} =
      OptionParser.parse(args,
        switches: [files: :string, output: :string],
        aliases: [f: :files, o: :string]
      )

    otp_app = Mix.Project.config()[:app]

    pattern = Keyword.get(opts, :files) || "assets/js/ash_rpc/*.json"
    output_file = Keyword.get(opts, :output) || "assets/js/ash_rpc.ts"

    patterns = String.split(pattern, ",", trim: true)
    files = Enum.flat_map(patterns, &Path.wildcard/1) |> Enum.uniq()

    if files == [] do
      raise "No files matched the pattern: #{pattern}"
    end

    resources_and_actions =
      otp_app
      |> Ash.Info.domains()
      |> Enum.flat_map(fn domain ->
        AshTypescript.RPC.Info.rpc(domain)
      end)

    types =
      files
      |> Enum.flat_map(fn file ->
        file
        |> File.read!()
        |> Jason.decode!()
        |> List.wrap()
      end)
      |> Enum.reduce("", fn rpc_spec, content ->
        {resource, rpc_action} =
          Enum.find_value(resources_and_actions, fn %{
                                                      resource: resource,
                                                      rpc_actions: rpc_actions
                                                    } ->
            rpc_action =
              Enum.find(rpc_actions, fn rpc_action ->
                if to_string(rpc_action.name) == rpc_spec["action"] do
                  rpc_action.action
                end
              end)

            if rpc_action do
              {resource, rpc_action}
            end
          end)

        if rpc_action == nil do
          raise "Unable to find rpc_action #{rpc_action["name"]}"
        end

        action = Ash.Resource.Info.action(resource, rpc_action.action)
        primary_key = Ash.Resource.Info.primary_key(resource)
        loads = Helpers.parse_json_select_and_load(rpc_spec["load"] || [])
        select = Helpers.parse_json_select_and_load(rpc_spec["select"] || [])
        fields = (select ++ loads) |> Enum.uniq()

        input_type_name = "#{snake_to_pascal(rpc_action.name)}Input"

        input_type =
          case action.type do
            :read ->
              if Enum.empty?(action.arguments) do
                ""
              else
                """
                export type #{input_type_name} = {
                #{Enum.map_join(action.arguments, "\n", &get_action_argument_spec(&1))}
                }
                """
              end

            :update ->
              """
              export type #{input_type_name} = {
              #{Enum.map_join((primary_key ++ action.accept) |> Enum.uniq(), "\n", &get_action_accept_spec(&1, resource))}
              #{Enum.map_join(action.arguments, "\n", &get_action_argument_spec(&1))}
              }
              """

            _ ->
              """
              export type #{input_type_name} = {
              #{Enum.map_join(action.arguments, "\n", &get_action_argument_spec(&1))}
              #{Enum.map_join(action.accept, "\n", &get_action_accept_spec(&1, resource))}
              }
              """
          end

        return_type_name = "#{snake_to_pascal(rpc_action.name)}Return"

        return_type =
          """
          export type #{return_type_name} = {
          #{Enum.map_join(fields,
          "\n",
          &get_field_spec(&1, resource))}
          }#{if action.type == :read and not action.get?, do: "[]", else: ""}
          """

        function =
          """
          export async function #{snake_to_camel(rpc_action.name)}(endpoint: string#{if input_type == "", do: "", else: ", input: #{input_type_name}"}): Promise<#{return_type_name}> {
            return await fetch(endpoint, {
              method: 'POST',
              headers: {
                'Content-Type': 'application/json'
              },
              body: JSON.stringify({action: "#{rpc_action.name}"#{if input_type == "", do: ", input: {}", else: ", input"}#{if Enum.empty?(rpc_spec["select"] || []), do: "select: []", else: ", select: #{Jason.encode!(rpc_spec["select"])}"}#{if Enum.empty?(rpc_spec["load"] || []), do: ", load: []", else: ", load: #{Jason.encode!(rpc_spec["load"])}"}})
            }).then(response => response.json())
          }
          """

        Enum.join([content, input_type, return_type, function], "\n")
      end)

    File.write!(output_file, types)
  end

  defp snake_to_pascal(snake) when is_atom(snake) do
    snake
    |> Atom.to_string()
    |> snake_to_pascal()
  end

  defp snake_to_pascal(snake) when is_binary(snake) do
    snake
    |> String.split("_")
    |> Enum.with_index()
    |> Enum.map(fn {part, _} -> String.capitalize(part) end)
    |> Enum.join()
  end

  defp snake_to_camel(snake) when is_atom(snake) do
    snake
    |> Atom.to_string()
    |> snake_to_camel()
  end

  defp snake_to_camel(snake) when is_binary(snake) do
    snake
    |> String.split("_")
    |> Enum.with_index()
    |> Enum.map(fn
      {part, 0} -> String.downcase(part)
      {part, _} -> String.capitalize(part)
    end)
    |> Enum.join()
  end

  defp get_field_spec(field, resource) when is_atom(field) do
    attributes =
      if field == :id,
        do: [Ash.Resource.Info.attribute(resource, :id)],
        else: Ash.Resource.Info.public_attributes(resource)

    calculations = Ash.Resource.Info.public_calculations(resource)
    aggregates = Ash.Resource.Info.public_aggregates(resource)

    with nil <- Enum.find(attributes, &(&1.name == field)),
         nil <- Enum.find(calculations, &(&1.name == field)),
         nil <- Enum.find(aggregates, &(&1.name == field)) do
      throw("Field not found: #{resource}.#{field}")
    else
      %Ash.Resource.Attribute{} = attr ->
        if attr.allow_nil? do
          "  #{field}?: #{get_ts_type(attr.type)} | null;"
        else
          "  #{field}: #{get_ts_type(attr.type)};"
        end

      %Ash.Resource.Calculation{} = calc ->
        if calc.allow_nil? do
          "  #{field}?: #{get_ts_type(calc.type)} | null;"
        else
          "  #{field}: #{get_ts_type(calc.type)};"
        end

      %Ash.Resource.Aggregate{} = agg ->
        type =
          case agg.kind do
            :sum ->
              resource
              |> lookup_aggregate_type(agg.relationship_path, agg.field)
              |> get_ts_type()

            :first ->
              resource
              |> lookup_aggregate_type(agg.relationship_path, agg.field)
              |> get_ts_type()

            _ ->
              get_ts_type(agg.kind)
          end

        if agg.include_nil? do
          "  #{field}?: #{type} | null;"
        else
          "  #{field}: #{type};"
        end

      field ->
        throw("Unknown field type: #{inspect(field)}")
    end
  end

  defp get_field_spec({field_name, fields}, resource) do
    relationships = Ash.Resource.Info.public_relationships(resource)

    case Enum.find(relationships, &(&1.name == field_name)) do
      nil ->
        throw("Relationship not found on #{resource}: #{field_name}")

      %Ash.Resource.Relationships.HasMany{} = rel ->
        id_fields = Ash.Resource.Info.primary_key(resource)
        fields = Enum.uniq(fields ++ id_fields)

        "  #{field_name}: {#{Enum.map_join(fields, "\n", &get_field_spec(&1, rel.destination))}\n}[];\n"

      rel ->
        id_fields = Ash.Resource.Info.primary_key(resource)
        fields = Enum.uniq(fields ++ id_fields)

        if rel.allow_nil? do
          "  #{field_name}: {#{Enum.map_join(fields, "\n", &get_field_spec(&1, rel.destination))}} | null;"
        else
          "  #{field_name}: {#{Enum.map_join(fields, "\n", &get_field_spec(&1, rel.destination))}};\n"
        end
    end
  end

  defp get_action_accept_spec(attr, resource) do
    attribute = Ash.Resource.Info.attribute(resource, attr)

    if attribute.allow_nil? or attribute.default != nil do
      "  #{attr}?: #{get_ts_type(attribute.type)} | null;"
    else
      "  #{attr}: #{get_ts_type(attribute.type)};"
    end
  end

  defp get_action_argument_spec(argument) do
    if argument.allow_nil? or argument.default != nil do
      "  #{argument.name}?: #{get_ts_type(argument.type)} | null;"
    else
      "  #{argument.name}: #{get_ts_type(argument.type)};"
    end
  end

  defp lookup_aggregate_type(current_resource, [], field) do
    Ash.Resource.Info.attribute(current_resource, field)
    |> Map.get(:type)
  end

  defp lookup_aggregate_type(current_resource, relationship_path, field) do
    [next_resource | rest] = relationship_path

    relationship =
      Enum.find(Ash.Resource.Info.relationships(current_resource), &(&1.name == next_resource))

    lookup_aggregate_type(relationship.destination, rest, field)
  end

  defp get_ts_type(:count), do: "number"
  defp get_ts_type(Ash.Type.Atom), do: "string"
  defp get_ts_type(Ash.Type.UUID), do: "string"
  defp get_ts_type(AshDoubleEntry.ULID), do: "string"
  defp get_ts_type(Ash.Type.String), do: "string"
  defp get_ts_type(Ash.Type.UtcDatetime), do: "string"
  defp get_ts_type(Ash.Type.UtcDatetimeUsec), do: "string"
  defp get_ts_type(Ash.Type.Date), do: "string"
  defp get_ts_type(Ash.Type.DateTime), do: "string"
  defp get_ts_type(Ash.Type.Time), do: "string"
  defp get_ts_type(Ash.Type.Map), do: "Record<string, any>"
  defp get_ts_type(Ash.Type.CiString), do: "string"
  defp get_ts_type(Ash.Type.Integer), do: "number"
  defp get_ts_type(Ash.Type.Boolean), do: "boolean"
  defp get_ts_type(Ash.Type.Float), do: "number"
  defp get_ts_type(Ash.Type.Keyword), do: "string"
  defp get_ts_type(AshMoney.Types.Money), do: "{currency: string, amount: string}"

  defp get_ts_type(maybe_enum) when is_atom(maybe_enum) do
    if Spark.implements_behaviour?(maybe_enum, Ash.Type.Enum) do
      maybe_enum.values() |> Enum.map(&"\"#{to_string(&1)}\"") |> Enum.join(" | ")
    else
      raise "Unknown type: #{inspect(maybe_enum)}"
    end
  end
end
