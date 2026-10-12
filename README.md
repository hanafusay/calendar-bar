# Calendar Bar

Google カレンダーの今日の予定を、Mac のメニューバーに表示するアプリです。
SwiftBar、Homebrew、Python、外部CLI、Mac のカレンダーアプリは不要です。

## インストールする

GitHub Releases から DMG をダウンロードします。
DMG を開き、Calendar Bar.app を Applications にドラッグします。
Applications から Calendar Bar を開きます。

最初の配布版はアドホック署名です。
macOS が起動を止めた場合は、システム設定 > プライバシーとセキュリティ > このまま開く、で許可します。
プロジェクトのリリースから取得したアプリであることを先に確認してください。

## Google を接続する

利用者が、自分の Google Cloud のデスクトップ用認証クライアントを用意します。
OAuth は、パスワードをアプリに渡さず、Google の画面でアクセスを許可する認証方式です。
配布アプリには、配布者の Google 認証クライアントも利用者のログイン情報も入っていません。

1. Google Cloud の自分のプロジェクトで Google Calendar API を有効にします。
2. Google Auth Platform で同意画面を設定します。
3. 外部向けのテスト状態を使う場合は、自分の Google アカウントをテストユーザーに追加します。
4. 種類が「デスクトップ アプリ」の OAuth クライアントを作成し、JSON をダウンロードします。
5. Calendar Bar の設定で認証ファイルを選びます。
6. Google に接続し、予定の読み取りを許可します。

認証ファイルと接続後の認証情報は、Mac のキーチェーンへ保存します。
アプリは予定の変更・削除を行いません。
外部向けのテスト状態では、Google が更新用の認証情報を7日で失効させるため、再接続が必要になります。
職場のアカウントでは、管理者がアプリへのアクセスを制限する場合があります。

[Google のデスクトップ認証の手順](https://developers.google.com/identity/protocols/oauth2/native-app)
[Google の認証情報の有効期間](https://developers.google.com/identity/protocols/oauth2)

## 予定を確認する

- メニューバーに現在の予定を表示します。現在の予定がなければ、次の予定と開始までの時間を表示します。
- メニューに今日の予定を時刻順で表示します。終了済みの予定は灰色です。
- 予定のメニューから Meet または Google カレンダーを開けます。
- 予定は1分ごとに更新します。「今すぐ更新」でも取得できます。
- 終日、勤務場所、取消済み、自分が辞退した予定は除外します。

時刻と日付の境界には Mac のタイムゾーンを使います。
予定を取得できなかった場合は、更新に失敗したことと最後に成功した更新日時を表示します。

## ソースからビルドする

Xcode Command Line Tools と Swift が必要です。

```sh
swift run CalendarChecks
./create-dmg.sh
open "dist/Calendar Bar.app"
```

Apple Silicon と Intel Mac の両方で動く実行ファイルを DMG に含めます。
`dist/` とローカルの認証ファイルは Git へ登録しません。

## 配布者が署名する

Developer ID による署名と Apple の公証は任意です。
通常のビルドはアドホック署名を使い、Apple Developer への有料登録を必要としません。

署名を追加する場合は、Developer ID Application 証明書をキーチェーンへ入れます。
公証は、Apple が配布物を検査する工程です。
`notarytool` に認証情報を保存した後、次の形で作成します。

```sh
SIGNING_IDENTITY="Developer ID Application: YOUR NAME (TEAMID)" \
NOTARY_PROFILE="calendar-bar-notary" ./create-dmg.sh
```

秘密鍵や Apple の認証情報を Git または配布ファイルへ追加しないでください。
[Apple の署名と公証](https://developer.apple.com/developer-id/)

## プライバシー

認証情報は利用者の Mac に保存します。
予定の取得先は Google です。
解析サービス、配布者のサーバー、テレメトリーへ予定を送信しません。

## ライセンス

MIT。LICENSE を参照してください。
