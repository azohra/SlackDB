defmodule SlackDB.Utils do
  @moduledoc false

  # @emoji_list_regex ~r/:[^:]+:/

  @key_type_regex ":thumbsup:|:family:|:hear_no_evil:|:monkey:"
  @key_schema ~r/(?<key_phrase>.+)\s(?<key_type>#{@key_type_regex})(?<more_metadata>.*)/

  @emoji_to_metadata %{
    ":thumbsup:" => :voting,
    ":family:" => :multiple,
    ":hear_no_evil:" => :single_front,
    ":monkey:" => :single_back,
    ":do_not_litter:" => :constant,
    ":anchor:" => :undeletable
    # ":octagonal_sign:" => :locked,
  }

  @metadata_to_emoji %{
    voting: ":thumbsup:",
    multiple: ":family:",
    single_front: ":hear_no_evil:",
    single_back: ":monkey:",
    constant: ":do_not_litter:",
    undeletable: ":anchor:"
    # locked: ":octagonal_sign:",
  }
  ####################################################################################
  ## HIGH LEVEL UTILITIES ############################################################
  ####################################################################################

  ####################################################################################
  ## SLACKDB HELPERS #################################################################
  ####################################################################################

  @spec get_tokens(term(), list(atom())) :: list() | {:error, String.t()}
  def get_tokens(server_name, key_list) do
    try do
      server =
        Application.get_env(:slackdb, :servers)
        |> Map.fetch!(server_name)

      for key <- key_list, do: Map.fetch!(server, key)
    rescue
      e in KeyError -> {:error, "KeyError: couldn't find key #{e.key}"}
    end
  end

  def check_schema(phrase) do
    Regex.named_captures(@key_schema, phrase)
  end

  def metadata_to_emoji(metadata) when is_atom(metadata) do
    Map.get(@metadata_to_emoji, metadata, ":question:")
  end

  def emoji_to_metadata(emoji) when is_binary(emoji) do
    Map.get(@emoji_to_metadata, emoji, :unknown_emoji)
  end

  ####################################################################################
  ## GENERIC HELPERS #################################################################
  ####################################################################################

  # like Kernel.put_in but it can add a k/v pair to an existing nested map rather than only update the value
  def put_kv_in(map, [], new_key, new_value),
    do: Map.put(map, new_key, new_value)

  def put_kv_in(map, [head | tail], new_key, new_value) do
    Map.put(map, head, put_kv_in(map[head], tail, new_key, new_value))
  end
end
