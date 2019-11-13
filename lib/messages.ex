defmodule SlackDB.Messages do
  alias SlackDB.Client

  def post_thread(bot_token, channel_id, text, thread_ts) when is_binary(text),
    do: post_thread(bot_token, channel_id, [text], thread_ts)

  def post_thread(bot_token, channel_id, [last_text], thread_ts),
    do: [Client.chat_postMessage(bot_token, last_text, channel_id, thread_ts)]

  def post_thread(bot_token, channel_id, [first_text | more_posts], thread_ts) do
    [
      Client.chat_postMessage(bot_token, first_text, channel_id, thread_ts)
      | post_thread(bot_token, channel_id, more_posts, thread_ts)
    ]
  end

  def wipe_thread(user_token, key, include_key?) do
    with {:ok, resp} <- Client.conversations_replies(user_token, key) do
      case include_key? do
        false -> get_all_replies(user_token, key, [], resp)
        true -> get_all_replies(user_token, key, [%{"ts" => key.ts}], resp)
      end
      |> Flow.from_enumerable()
      |> Flow.map(fn %{"ts" => ts} -> Client.chat_delete(user_token, key.channel_id, ts) end)
      |> Enum.to_list()

      # |> Enum.map(fn %{"ts" => ts} -> Client.chat_delete(user_token, key.channel_id, ts) end)
    else
      err -> err
    end
  end

  # paginate through conversations.replies responeses and collect all replies to a key in a list, chronologically
  def get_all_replies(_user_token, _key, array, %{"has_more" => false} = response) do
    [_key_message | replies] = response["messages"]
    replies ++ array
  end

  def get_all_replies(
        user_token,
        key,
        array,
        %{"has_more" => true, "response_metadata" => %{"next_cursor" => cursor}} = response
      ) do
    [_key_message | replies] = response["messages"]

    with {:ok, next_response} <- Client.conversations_replies(user_token, key, cursor) do
      get_all_replies(
        user_token,
        key,
        replies ++ array,
        next_response
      )
    end
  end
end
