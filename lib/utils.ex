defmodule SlackDB.Utils do
  @moduledoc false

  @emoji_list_regex ~r/:[^:]+:/

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

  def check_schema(phrase) do
    Regex.named_captures(@key_schema, phrase)
  end

  def metadata_to_emoji(metadata) when is_atom(metadata) do
    @metadata_to_emoji[metadata]
  end

  def emoji_to_metadata(emoji) when is_binary(emoji) do
    @emoji_to_metadata[emoji]
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
