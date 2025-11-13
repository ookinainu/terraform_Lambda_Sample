# Terraform AWS Infrastructure (Lambda + RDS + VPC)

## 構成概要
- VPC (Private Subnet 1a,1c)
- Lambda (Python 3.12, VPC内)
- RDS MySQL 8.0 (Multi-AZ)
- Secrets Manager (DB接続情報)
- API Gateway（HTTP API）
- EventBridge（毎日0時に Lambda を起動）

## デプロイ方法
terraform init
terraform plan
terraform apply

## ディレクトリ構成
├── main.tf
├── lambda/
│   └── handler.py
└── README.md