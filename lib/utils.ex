defmodule SlackDB.Utils do
  @moduledoc false
  use Private
  alias SlackDB.Client

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

  ####################################################################################
  ## HIGH LEVEL UTILITIES ############################################################
  ####################################################################################

  # @spec search(String.t(), String.t(), String.t(), boolean()) ::
  #         {:ok, SlackDB.Key.t()} | {:error, String.t()}
  # def search(server_name, channel_name, key_phrase, only_bot?)

  # def search(server_name, channel_name, key_phrase, true) do
  #   with %{user_token: user_token, bot_name: bot_name} <-
  #          Application.get_env(:slackdb, :servers) |> Map.get(server_name),
  #        {:ok, match_info} <-
  #          Client.search_messages(
  #            user_token,
  #            "in:##{channel_name} from:#{bot_name} \"#{key_phrase}\""
  #          ),
  #        {:ok, key} <- parse_matches(match_info) do
  #     {:ok, key |> Map.put(:server_name, server_name)}
  #   else
  #     nil -> {:error, "server_not_found_in_config"}
  #     %{} -> {:error, "improper_config"}
  #     err -> err
  #   end
  # end

  # def search(server_name, channel_name, key_phrase, false) do
  #   with %{user_token: user_token} <-
  #          Application.get_env(:slackdb, :servers) |> Map.get(server_name),
  #        {:ok, match_info} <-
  #          Client.search_messages(user_token, "in:##{channel_name} \"#{key_phrase}\""),
  #        {:ok, key} <- parse_matches(match_info) do
  #     {:ok, key |> Map.put(:server_name, server_name)}
  #   else
  #     nil -> {:error, "server_not_found_in_config"}
  #     %{} -> {:error, "improper_config"}
  #     err -> err
  #   end
  # end

  # def post_thread(bot_token, channel_id, text, thread_ts) when is_binary(text),
  #   do: post_thread(bot_token, channel_id, [text], thread_ts)

  # def post_thread(bot_token, channel_id, [last_text], thread_ts),
  #   do: [Client.chat_postMessage(bot_token, last_text, channel_id, thread_ts)]

  # def post_thread(bot_token, channel_id, [first_text | more_posts], thread_ts) do
  #   [
  #     Client.chat_postMessage(bot_token, first_text, channel_id, thread_ts)
  #     | post_thread(bot_token, channel_id, more_posts, thread_ts)
  #   ]
  # end

  # def wipe_thread(user_token, key, include_key?) do
  #   with {:ok, resp} <- Client.conversations_replies(user_token, key) do
  #     case include_key? do
  #       false -> get_all_replies(user_token, key, [], resp)
  #       true -> get_all_replies(user_token, key, [%{"ts" => key.ts}], resp)
  #     end
  #     |> Flow.from_enumerable()
  #     |> Flow.map(fn %{"ts" => ts} -> Client.chat_delete(user_token, key.channel_id, ts) end)
  #     |> Enum.to_list()

  #     # |> Enum.map(fn %{"ts" => ts} -> Client.chat_delete(user_token, key.channel_id, ts) end)
  #   else
  #     err -> err
  #   end
  # end

  # # paginate through conversations.list responeses and collect public+private channels in a list
  # def get_all_convos(
  #       _user_token,
  #       array,
  #       %{"channels" => channels, "response_metadata" => %{"next_cursor" => ""}}
  #     ) do
  #   channels ++ array
  # end

  # def get_all_convos(
  #       user_token,
  #       array,
  #       %{"channels" => channels, "response_metadata" => %{"next_cursor" => cursor}}
  #     ) do
  #   with {:ok, next_response} <- Client.conversations_list(user_token, cursor) do
  #     get_all_convos(
  #       user_token,
  #       channels ++ array,
  #       next_response
  #     )
  #   end
  # end

  ####################################################################################
  ## SLACKDB HELPERS #################################################################
  ####################################################################################

  def check_schema(phrase) do
    Regex.named_captures(@key_schema, phrase)
  end

  # private do
  #   defp parse_matches(%{"matches" => matches, "total" => total}) do
  #     case total do
  #       0 -> {:error, "no_search_matches"}
  #       _number -> first_matched_schema(matches)
  #     end
  #   end

  #   # recurses through an array of search results, creating a %SlackDB.Key{} out of the first one that matches the key schema
  #   defp first_matched_schema([head]) do
  #     check_schema(head["text"])
  #     |> case do
  #       nil ->
  #         {:error, "no_search_result_matching_key_schema"}

  #       %{
  #         "key_phrase" => key_phrase,
  #         "key_type" => key_type,
  #         "more_metadata" => more_metadata
  #       } ->
  #         {:ok,
  #          %SlackDB.Key{
  #            key_phrase: key_phrase,
  #            metadata: [
  #              @emoji_to_metadata[key_type]
  #              | Regex.scan(@emoji_list_regex, more_metadata)
  #                |> List.flatten()
  #                |> Enum.map(fn x -> @emoji_to_metadata[x] end)
  #            ],
  #            channel_id: head["channel"]["id"],
  #            ts: head["ts"],
  #            channel_name: head["channel"]["name"]
  #          }}
  #     end
  #   end

  #   defp first_matched_schema([head | tail]) do
  #     check_schema(head["text"])
  #     |> case do
  #       nil ->
  #         first_matched_schema(tail)

  #       %{
  #         "key_phrase" => key_phrase,
  #         "key_type" => key_type,
  #         "more_metadata" => more_metadata
  #       } ->
  #         {:ok,
  #          %SlackDB.Key{
  #            key_phrase: key_phrase,
  #            metadata: [
  #              @emoji_to_metadata[key_type]
  #              | Regex.scan(@emoji_list_regex, more_metadata)
  #                |> List.flatten()
  #                |> Enum.map(fn x -> @emoji_to_metadata[x] end)
  #            ],
  #            channel_id: head["channel"]["id"],
  #            ts: head["ts"],
  #            channel_name: head["channel"]["name"]
  #          }}
  #     end
  #   end
  # end

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
