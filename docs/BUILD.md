# 自分の署名で Calendar Bar をビルドする

予定表示の開発は `swift run CalendarBar --demo` で行えます。
Google 接続を使う独自の配布版は、自分の証明書でアプリと認証用部品を署名します。
公式の秘密鍵を提供することはありません。

## 自分の署名を設定する

1. リポジトリをフォークします。
2. 自分のコード署名用の自己署名証明書を作ります。Apple Developer の有料登録は不要です。
3. 公開証明書を PEM 形式で `Resources/SigningCertificate.pem` に保存します。秘密鍵を含むファイルは Git に追加しません。
4. 公開証明書の SHA-1 フィンガープリントを確認します。フィンガープリントは証明書を識別する公開の値です。

   ```sh
   openssl x509 -in Resources/SigningCertificate.pem -noout -fingerprint -sha1
   ```

5. `Sources/CredentialProtocol/CredentialProtocol.swift` の証明書フィンガープリントを、自分の証明書の値へ変更します。コロンを取り除いた40桁の値を使います。
6. 証明書と秘密鍵をパスワード付き P12 に書き出します。フォークの GitHub Secrets に、P12 の Base64 を `CALENDAR_SIGNING_P12`、P12 のパスワードを `CALENDAR_SIGNING_PASSWORD` として登録します。秘密の値をコード、ログ、Issue へ書きません。

## 認証用部品を一度作る

1. 自分のフォークで **Release DMG** を手動実行し、**bootstrap_credentials** を有効にします。
2. 架空の認証情報を使う検査が成功したことを確認します。本人の Google 認証情報を検査へ入れません。
3. 実行結果の **credential-service-v1** から、署名済みアーカイブとチェックサムを取得します。
4. `CalendarCredentials-v1.tar.gz` と `CalendarCredentials-v1.tar.gz.sha256` を `Resources/` に保存してコミットします。認証用部品の公開バイナリには、利用者の認証情報や署名の秘密鍵は含まれません。

通常のアプリ更新では、署名済みアーカイブを作り直しません。
アプリのビルドと署名は、同梱した認証用部品の中身を変更しません。

## DMG を作る

自分のフォークで **Release DMG** を、**bootstrap_credentials** を無効にして手動実行します。
作成された下書きの DMG を自分の Mac で確認してから公開します。
通常のアプリ更新でも、同じ証明書と秘密鍵を使います。

認証用部品の修正や署名鍵の変更では、Mac が再許可を求める可能性があります。
認証用部品を作り直す前に、新しい部品を使った移行を検証します。
