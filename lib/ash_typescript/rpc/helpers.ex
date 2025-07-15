defmodule AshTypescript.Rpc.Helpers do
  def parse_json_load(list, formatter \\ nil) when is_list(list) do
    list
    |> Enum.map(&transform(&1, formatter))
    |> reorder_atoms_and_keywords()
  end

  defp transform(%{} = map, formatter) when map_size(map) == 1 do
    [{k, v}] = Map.to_list(map)
    formatted_key = format_field_name(k, formatter)
    {formatted_key, parse_json_load(v, formatter)}
  end

  defp transform(str, formatter) when is_binary(str) do
    format_field_name(str, formatter)
  end
  
  defp transform(atom, _formatter) when is_atom(atom), do: atom

  defp format_field_name(field_name, nil) when is_binary(field_name) do
    String.to_atom(field_name)
  end
  
  defp format_field_name(field_name, formatter) when is_binary(field_name) do
    AshTypescript.FieldFormatter.parse_input_field(field_name, formatter)
  end

  defp reorder_atoms_and_keywords(items) do
    {atoms, keywords} = Enum.split_with(items, &is_atom/1)
    atoms ++ keywords
  end
end
