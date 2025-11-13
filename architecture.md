┌────────────────────────────────────────────────────────────────────────┐
│                            AWS ACCOUNT                                 │
│                                                                        │
│  ┌────────────────────────────────────────────────────────────────┐   │
│  │                          VPC (10.0.0.0/16)                     │   │
│  │  enable_dns_support   = true                                   │   │
│  │  enable_dns_hostnames = true                                   │   │
│  │                                                                │   │
│  │  ┌────────────────────────────────────────────┐                │   │
│  │  │ Private Subnet 1a (10.0.10.0/24)           │                │   │
│  │  │ Private Subnet 1c (10.0.20.0/24)           │                │   │
│  │  │                                              │              │   │
│  │  │ [LAMBDA] aws-daily-job                       │              │   │
│  │  │  - Runtime: Python 3.12                      │              │   │
│  │  │  - Handler: handler.lambda_handler           │              │   │
│  │  │  - SG: Lambda_SG (egress all)                │              │   │
│  │  │  - Runs inside VPC, connects to RDS          │              │   │
│  │  │  - Reads DB credentials via Secrets Manager  │              │   │
│  │  │                                              │              │   │
│  │  │ [RDS] MySQL 8.0                              │              │   │
│  │  │  - Subnet Group: SubGroup_1a_1C              │              │   │
│  │  │  - Multi-AZ enabled                          │              │   │
│  │  │  - SG: RDS_SG (3306 inbound from Lambda)     │              │   │
│  │  │  - Public access: false                      │              │   │
│  │  │                                              │              │   │
│  │  │ [VPC ENDPOINT] Secrets Manager               │              │   │
│  │  │  - Service: com.amazonaws.ap-northeast-1.secretsmanager     │   │
│  │  │  - Subnets: 1a, 1c                           │              │   │
│  │  │  - SG: Terra_VPC_SG (443 allowed)            │              │   │
│  │  └────────────────────────────────────────────┘                │   │
│  └────────────────────────────────────────────────────────────────┘   │
│                                                                       │
│       ▲                                                               │
│       │ (invoke)                                                      │
│   ┌──────────────┐                                                    │
│   │ API Gateway  │──▶ Lambda (inside VPC)                             │
│   │  protocol: HTTP API (v2.0)                                        │
│   │  route: GET /lambda                                               │
│   │  integration: AWS_PROXY → Lambda                                  │
│   │  stage: $default (auto deploy)                                    │
│   └──────────────┘                                                    │
│       ▲                                                               │
│       │ (trigger)                                                     │
│   ┌──────────────┐                                                    │
│   │ EventBridge  │──▶ Lambda (daily batch)                            │
│   │  cron(0 15 * * ? *) → JST 0:00                                    │
│   └──────────────┘                                                    │
│                                                                        │
│   IAM Role: lambda-role                                                │
│    - AWSLambdaVPCAccessExecutionRole                                   │
│    - AWSLambdaBasicExecutionRole                                       │
│    - Custom Policy (SecretsManager:GetSecretValue)                     │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
