defmodule AshTypescript.Rpc.Helpers do
  def parse_json_load(list) when is_list(list) do
    list
    |> Enum.map(&transform/1)
    |> reorder_atoms_and_keywords()
  end

  defp transform(%{} = map) when map_size(map) == 1 do
    [{k, v}] = Map.to_list(map)
    {String.to_existing_atom(k), parse_json_load(v)}
  end

  defp transform(str) when is_binary(str), do: String.to_atom(str)
  defp transform(atom) when is_atom(atom), do: atom

  defp reorder_atoms_and_keywords(items) do
    {atoms, keywords} = Enum.split_with(items, &is_atom/1)
    atoms ++ keywords
  end
end
