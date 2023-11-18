from flask import Flask, request, abort

from linebot import (
    LineBotApi, WebhookHandler
)
from linebot.exceptions import (
    InvalidSignatureError
)
from linebot.models import (
    MessageEvent, TextMessage, TextSendMessage, QuickReplyButton, MessageAction, QuickReply,
)

app = Flask(__name__)

line_bot_api = LineBotApi('kTfN4wT4SSQoOgAFETCcJ4j5G0tncWYBCpkj/UysXIYfhqChAOQ0c58xFmlquZs9SQ8pk54Yv/2HOzuhpEFSM9BN0P6Wc9S1xfzTJOSNf6zHtgO/6mEfhBv6gUKwypdzHrkxAtEZk5V95BfJZqySbgdB04t89/1O/w1cDnyilFU=')
handler = WebhookHandler('U8f10d5439785fedc7ba6681c26a738f2')

lesson = {
    '月曜日の時間割':'月曜日は\n1:こくご\n2:たいいく\n3:さんすう\nです。',
    '火曜日の時間割':'火曜日は\n1~2:りかじっけん\n3:こくご\nです。',
    '水曜日の時間割':'水曜日は\n1:さんすう\n2:おんがく\n3:せいかつ\nです。',
    '木曜日の時間割':'木曜日は\n1:たいいく\n2:かていか\n3:りか\nです。',
    '金曜日の時間割':'金曜日は\n1:さんすう\n2:こくご\n3:がっかつ\nです。',
    '土曜日の時間割':'月曜日は\n1:こくご\n2:たいいく\n3:さんすう\nです。'
}

@app.route("/")
def hello_world():
    return "hello world!"

@app.route("/callback", methods=['POST'])
def callback():
    # get X-Line-Signature header value
    signature = request.headers['X-Line-Signature']

    # get request body as text
    body = request.get_data(as_text=True)
    app.logger.info("Request body: " + body)

    # handle webhook body
    try:
        handler.handle(body, signature)
    except InvalidSignatureError:
        abort(400)

    return 'OK'


@handler.add(MessageEvent, message=TextMessage)
def handle_message(event):
    if event.message.text =='時間割を教えて':
        day_list = ["月", "火", "水", "木", "金", "土"]
        items = [QuickReplyButton(action=MessageAction(label=f"{day}", text=f"{day}曜日の時間割")) for day in day_list]
        messages = TextSendMessage(text="何曜日の時間割ですか？",quick_reply=QuickReply(items=items))
        line_bot_api.reply_message(event.reply_token, messages=messages)
    elif event.message.text in lesson:
        line_bot_api.reply_message(
            event.reply_token,
            TextMessage(text=lesson[event.message.text])
        )

    '''
    line_bot_api.reply_message(
        event.reply_token,
        TextSendMessage(text=event.message.text))
    '''

if __name__ == "__main__":
    app.run()

