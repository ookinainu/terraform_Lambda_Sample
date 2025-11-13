
#json関連の標準ライブラリ
import json
#OS関連の標準ライブラリ
import os
#pythonでmysqlにアクセスするためのライブラリ
import pymysql
#AWSのサービスと接続可能なライブラリ
#Lambda自動化運用における最重要エンジン
import boto3

#Secrets ManagerからRDSの接続情報を取得
def _get_secret():
    #boto3はclientメソッドにて引数の値を元にAWS APIの機能を内包したオブジェクトを生成
    #引数の値を変えれば別のサービスとの接続が可能
    #下記の変数smはAWSのシークレットマネージャーオブジェクト
    #Java同様、importすればインスタンスしなくても標準メソッドは使用可能
    sm = boto3.client("secretsmanager")
    #環境変数SECRET_ARN(terraform)を取得して変数SecretIdにセット
    #get_secret_valueメソッドで引数SecretIdにまつわる辞書型の値を取得
    #辞書型の値にキーを指定。SecretStringに関する情報を取得
    val = sm.get_secret_value(SecretId=os.environ["SECRET_ARN"])["SecretString"]
    #上記の値をセットした変数valを辞書型へ変換
    data = json.loads(val)
    #戻り値にシークレットマネージャーから取り出したユーザーネームとパスワードをセット
    #辞書型の変数[キー]で応対する値にアクセス可能
    return data["username"], data["password"]

#Lambdaのエントリポイント＆RDS接続
def lambda_handler(event, context):
    #環境変数からRDSのホスト名とデータベース名を取得
    host = os.environ["DB_HOST"]
    db   = os.environ["DB_NAME"]
    #上記のメソッドを実行。ユーザーネームとパスワードを取得
    user, pwd = _get_secret()
    #RDS(MySQL)へ接続
    conn = pymysql.connect(
        host=host, user=user, password=pwd, database=db, connect_timeout=5
    )

    try:
        #with句は句の中で処理が終われば自動でリソースを閉じる
        #エラーが出た場合はその時点で処理がクローズする
        #DB操作を行うカーソルを取得
        with conn.cursor() as cur:
            #以下のSQLを実行
            #IF NOT EXISTSで既に作成済の場合はCREATEの処理なし
            cur.execute("""
                CREATE TABLE IF NOT EXISTS daily_logs(
                  id BIGINT AUTO_INCREMENT PRIMARY KEY,
                  run_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );
            """)
            #以下のSQLを実行
            cur.execute("INSERT INTO daily_logs() VALUES()")
        #SQL操作を確定
        conn.commit()
        #以下の値を戻り値へ
        return {"status": "ok"}
    #上記の処理が終了した場合
    finally:
        #RDS接続を終了
        conn.close()
