# Terraform AWS Infrastructure Example
# 構築構成：VPC、RDS、Lambda（個人学習環境用）


#プロバイダー指定
provider "aws" {
    region = "ap-northeast-1"
}

#VPC
resource "aws_vpc" "Terra_VPC"{
	cidr_block="10.0.0.0/16"
    #VPCエンドポイントがプライベート領域に居るLambdaをDNS化するのに必要
    #ENIで振られたプラIPをDNSでパブIPへ変換
    enable_dns_support   = true 
    enable_dns_hostnames = true
	tags={
		Name="aws_VPC_API"
		}
}

#Privateサブネット-1a
resource "aws_subnet" "Terra_Pri_Subnet1a"{
	vpc_id=aws_vpc.Terra_VPC.id
	cidr_block="10.0.10.0/24"
	availability_zone = "ap-northeast-1a"

	tags={
		Name="aws_Pri_Subnet_API"
		}

}

#Privateサブネット-1c
resource "aws_subnet" "Terra_Pri_Subnet1c"{
	vpc_id=aws_vpc.Terra_VPC.id
	cidr_block="10.0.20.0/24"
	availability_zone = "ap-northeast-1c"

	tags={
		Name="aws_Pri_Subnet_API"
		}

}

#priルートテーブル（NATなし）
resource "aws_route_table" "Terra_Pri_RouteTable" {
    vpc_id = aws_vpc.Terra_VPC.id
}

#priルートテーブルとpriサブネットをアタッチ
resource "aws_route_table_association" "attatch_1a" {
    subnet_id      = aws_subnet.Terra_Pri_Subnet1a.id
    route_table_id = aws_route_table.Terra_Pri_RouteTable.id
}

#priルートテーブルとpriサブネットをアタッチ
resource "aws_route_table_association" "attatch_1c" {
    subnet_id      = aws_subnet.Terra_Pri_Subnet1c.id
    route_table_id = aws_route_table.Terra_Pri_RouteTable.id
}


#VPCエンドポイント①
#対インターネットではNAT、対AWSサービスではエンドポイントを利用
#ブロックがdataなのはエンドポイントにはサービス側とVPC側（ユーザー側）があるから
#以下はサービス側
data "aws_vpc_endpoint_service" "Terra_End_Ser" {
    service_name = "com.amazonaws.ap-northeast-1.secretsmanager"
    service_type = "Interface"
}

#VPCエンドポイント②
#対インターネットではNAT、対AWSサービスではエンドポイントを利用
#ブロックがdataなのはエンドポイントにはサービス側とVPC側（ユーザー側）があるから
#以下はVPC側
resource "aws_vpc_endpoint" "Terra_End_VPC" {
  vpc_id            = aws_vpc.Terra_VPC.id
  #サービス側のエンドポイントを指定
  service_name      = data.aws_vpc_endpoint_service.Terra_End_Ser.service_name
  vpc_endpoint_type = "Interface"
  #ENIを作成するサブネットを指定
  #ENI=(Elastic Network Interface)はネットワークの世界に参加するためのアイテム（TPアドレス等）
  #VPCエンドポイントはEC2やRDSと違い、最初からENIを持っていない
  subnet_ids        = [aws_subnet.Terra_Pri_Subnet1a.id, aws_subnet.Terra_Pri_Subnet1c.id]
  #VPCエンドポイント用のSGを指定
  security_group_ids = [aws_security_group.Terra_VPC_SG.id]
  #シークレットマネージャー=パスワード・APIキー・DB接続情報を安全に保管するサービス
  #つまりセキュリティを管理している
  #シークレットマネージャーの公開DNSをVPC内に作ったENIのプライベートIPに書き換える
  #ENI+エンドポイントはVPC外のAWSサービスを利用する上で鉄板
  private_dns_enabled = true
}

#VPCエンドポイントのSG
resource "aws_security_group" "Terra_VPC_SG" {
    name   = "vpc-sg"
    vpc_id = aws_vpc.Terra_VPC.id
    #HTTPSのポートを許可
    #VPCエンドポイントは443で通信するため
    ingress {
        from_port   = 443
        to_port     = 443
        protocol    = "tcp"
        cidr_blocks = [aws_vpc.Terra_VPC.cidr_block]
    }
    #AWS内部のサービスのために明記
    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

#Lambda用SG
resource "aws_security_group" "Lambda_SG" {
    name   = "lambda-sg"
    vpc_id = aws_vpc.Terra_VPC.id
    #AWS内部のサービスのために明記
    egress {
        protocol    = "-1"
        from_port   = 0
        to_port     = 0
        cidr_blocks = ["0.0.0.0/0"]
     }
}

#RDS用SG
resource "aws_security_group" "RDS_SG" {
    name   = "rds-sg"
    vpc_id = aws_vpc.Terra_VPC.id
    #Lambdaは3306で接続するため以下のポート番号を指定
    #Lambda_SGが適用されたリソースからはアクセス可能
    ingress {
        from_port       = 3306
        to_port         = 3306
        protocol        = "tcp"
        security_groups = [aws_security_group.Lambda_SG.id]
    }
    #AWS内部のサービスのために明記
    egress {
        protocol    = "-1"
        from_port   = 0
        to_port     = 0
        cidr_blocks = ["0.0.0.0/0"]
    }
}

#RDSのサブネットグループ
#サブネットグループ内のDBについてメインとサブに振り分けて自動で更新をデプロイ
resource "aws_db_subnet_group" "SubGroup_1a_1C" {
    name       = "rds-subnet"
    subnet_ids = [aws_subnet.Terra_Pri_Subnet1a.id, aws_subnet.Terra_Pri_Subnet1c.id]
}

#RDS作成
resource "aws_db_instance" "Terra_RDS_MySQL" {
    identifier                  = "demo-mysql"
    #RDSエンジン
    engine                      = "mysql"
    #MySQLのバージョンを指定
    engine_version              = "8.0"
    #RDSのインスタンスタイプ（メモリ/CPU）
    #SQLチューニングが必要な場合はこちらが関係
    instance_class              = "db.t4g.micro"
    #DBのストレージ容量（GB）
    allocated_storage           = 20
    #ストレージの種類（gp3=汎用SSD）
    storage_type                = "gp3"
    #作成するDB名
    db_name                     = "Lambda_db"
    #作成するDBユーザー名
    username                    = "admin"
    #パスワードをシークレットマネージャーが管理
    #作成されたパスワードはコンソールから確認可能
    manage_master_user_password = true
    #アタッチするSGを指定
    vpc_security_group_ids = [aws_security_group.RDS_SG.id]
    #RDSを配置するサブネットグループを指定
    db_subnet_group_name   = aws_db_subnet_group.SubGroup_1a_1C.name
    #パブリックアクセスは禁止
    publicly_accessible    = false

    #マルチAZ構成のため、スタンバイDBを自動で作成
    multi_az = true

    #学習環境のためスナップショットをスキップ
    #削除時間短縮
    skip_final_snapshot = true
}

#RDSが作成、シークレットマネージャーが管理するパスワード情報を変数化
#localsブロック=変数定義
#ARN=AWSリソースネーム
#RDS→locals→Lambdaで使用
locals {
    secret_arn = aws_db_instance.Terra_RDS_MySQL.master_user_secret[0].secret_arn 
}

#Lambdaがデプロイするzipの作成
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

#IAMロール作成
#Lamda→VPC(RDS)接続用
#許可証。誰ができるかを管理
#★重要★Lambdaはデバッグ機能がないので関数実装の際は同時に必ず実装
resource "aws_iam_role" "lambda_role" {
  name = "lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      #同ロールが適用されるAWSサービス
      Principal = { Service = "lambda.amazonaws.com" },
      #AWSでロールを引き受ける際は原則以下を記載
      Action   = "sts:AssumeRole"
    }]
  })
}

#既存の管理ポリシーを作成したIAMロールへアタッチ
#VPCアクセス権限を許可
resource "aws_iam_role_policy_attachment" "Terra_attatch_RandP" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

#既存の管理ポリシーを作成したIAMロールへアタッチ
#CloudWatch Logsへの書き込みを許可
resource "aws_iam_role_policy_attachment" "Terra_attatch_RandP2" {
    #対象ロールを指定
    role       = aws_iam_role.lambda_role.name
    #上記のロールにアタッチする既存の管理ポリシー
    policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

#IAMポリシー作成
#Lamda→VPC(RDS)接続用
#何ができるかを管理＝RDSのパスワード（SM管理）を読み取る権限
resource "aws_iam_policy" "lambda_policy_read" {
  name = "lambda-role-read"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      #LambdaがSecrets Managerから値を取得する権限
      Action = ["secretsmanager:GetSecretValue"],
      Resource = local.secret_arn
    }]
  })
}

#作成したIAMポリシーを作成したIAMロールへアタッチ
resource "aws_iam_role_policy_attachment" "Terra_attatch_RandP3" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy_read.arn
}

#Lambdaの設定
resource "aws_lambda_function" "Terra_job" {
    function_name = "aws-daily-job"
    #エントリポイントとなる関数を指定
    #handler=ファイル名.関数名
    handler = "handler.lambda_handler"
    #Lambdaに記載する言語を指定
    runtime = "python3.12"
    #Lambdaに渡すzipファイル名
    filename         = data.archive_file.lambda_zip.output_path
    #zipのハッシュ。コードが更新された時に自動デプロイを実施
    source_code_hash = data.archive_file.lambda_zip.output_base64sha256
    #上記で作成したIAMロールを指定
    role = aws_iam_role.lambda_role.arn

    #LambdaをVPC内で実行する設定
    vpc_config {
        subnet_ids         = [aws_subnet.Terra_Pri_Subnet1a.id, aws_subnet.Terra_Pri_Subnet1c.id]
        security_group_ids = [aws_security_group.Lambda_SG.id]
    }

    #Lambdaへ渡す環境変数
    #Lambdaは以下の環境変数を参照してバッチ処理を行う
    environment {
    variables = {
        #作成したRDSを指定
        DB_HOST    = aws_db_instance.Terra_RDS_MySQL.address
        #作成したDB名を指定
        DB_NAME    = "Lambda_db"
        #シークレットマネージャーが管理するRDSの接続情報を変数ARNへセット
        SECRET_ARN = local.secret_arn
    }
    }
}

#API Gateway作成
resource "aws_apigatewayv2_api" "Terra_APIGW" {
    name          = "APIGW-RDSbatti"
    protocol_type = "HTTP"
}

#LambdaとAPI Gatewayを接続（統合設定）
resource "aws_apigatewayv2_integration" "Terra_API_integration" {
    #使用するAPIGWの設定
    api_id                 = aws_apigatewayv2_api.Terra_APIGW.id
    #Lambda⇔API Gatewayのリクエストレスポンスを渡す方式
    #AWS_PROXY=操作なし。カスタム変換も可能
    integration_type       = "AWS_PROXY"
    #Terraform上のLambdaを指定。ここで指定したLambdaがAPIGWの次に呼び出される
    #HTTPリクエスト→APIGW→Lambda→lambdaのhandler
    integration_uri        = aws_lambda_function.Terra_job.invoke_arn
    #Lambda呼び出しの場合は常にPOST
    integration_method     = "POST"
    #ペイロード=API Gateway⇔Lambda間でやり取りされるデータ
    #HTTP API→2.0、REST API→1.0
    payload_format_version = "2.0"
}

#APIGWのルート（統合設定とリクエストメソッドを紐づけ）を作成
#以下はGETオンリー
resource "aws_apigatewayv2_route" "Terra_API_route" {
    #使用するAPIGWを指定
    api_id    = aws_apigatewayv2_api.Terra_APIGW.id
    #GETメソッドでLmabdaにアクセスした場合に同ルートが起動
    route_key = "GET /lambda"
    #どの統合設定に処理を渡すかを指定
    target    = "integrations/${aws_apigatewayv2_integration.Terra_API_integration.id}"
}

#ステージ作成
#API Gatewayの公開バージョン
resource "aws_apigatewayv2_stage" "Terra_API_stage" {
    #APIを指定
    api_id      = aws_apigatewayv2_api.Terra_APIGW.id
    #URLに付けるパスを指定
    #defaultの場合はフラットパス状態
    name        = "$default"
    #自動デプロイの設定
    auto_deploy = true
}

#リソースベースポリシーの作成
#誰からアクセスを受け入れるかを指定
#S3やLambda等に存在
resource "aws_lambda_permission" "allow_apigw_invoke" {
    #ポリシーの名前を作成
    statement_id  = "AllowExecutionFromAPIGateway"
    #許可する動作
    action        = "lambda:InvokeFunction"
    #許可する対象=どのLambdaかを指定
    function_name = aws_lambda_function.Terra_job.function_name
    #呼び出す対象
    #Lambdaを呼び出すのはAPIGWのため以下のサービスを指定
    principal     = "apigateway.amazonaws.com"
    #どのAPIかを指定
    #/*/*の2つのワイルドカードは /{stageOrDefault} / {method+route} を許す指定
    #→全ステージの全メソッド・全パスを許可
    source_arn = "${aws_apigatewayv2_api.Terra_APIGW.execution_arn}/*/*"
}

#EventBridge作成（スケジューラー）
#JST（日本時間）0:00実行
resource "aws_cloudwatch_event_rule" "Terra_EveBri" {
  name                = "lambda-daily-trigger"
  #バッチ処理の説明欄
  description         = "Run Lambda every day at 00:00 JST"
  #JST（日本時間）0:00=UTC15:00
  schedule_expression = "cron(0 15 * * ? *)"
}

#EventBridgeをLambdaに紐づけ
resource "aws_cloudwatch_event_target" "Terra_EveBri_target" {
    #使用するEventBridgeを指定
    rule      = aws_cloudwatch_event_rule.Terra_EveBri.name
    #EventBridgeルール内で一意となる任意の名前を指定
    target_id = "attatch-EveBri-lambda"
    #使用するAWSリソース（Lambda）を指定
    arn       = aws_lambda_function.Terra_job.arn
}

#リソースベースポリシーの作成
#誰からアクセスを受け入れるかを指定
#S3やLambda等に存在
resource "aws_lambda_permission" "allow_eventbridge_invoke" {
    #ポリシーの名前を作成
    statement_id  = "AllowExecutionFromEventBridge"
    #許可する動作    
    action        = "lambda:InvokeFunction"
    #許可する対象=どのLambdaかを指定
    function_name = aws_lambda_function.Terra_job.function_name
    #呼び出す対象
    #Lambdaを呼び出すのはEventBridgeのため以下のサービスを指定  
    principal     = "events.amazonaws.com"
    #使用するAWSリソース（EventBridge）を指定
    source_arn    = aws_cloudwatch_event_rule.Terra_EveBri.arn
}