terraform {
    required_providers {
        aws = {
            source = "hashicorp/aws"
            version = "~> 3.0"
        }
    }
}

provider "aws" {
    region = "us-east-1"
    access_key = var.access_key_id
    secret_key = var.secret_access_key
}

#================================================================
# Security Groups
#================================================================

resource "aws_security_group" "EC2SecurityGroup" {
    description = "Security group for the AWS Lambda Function"
    name = "sgr-test-lambda-prod"
    vpc_id = "${aws_vpc.EC2VPC.id}"
}


resource "aws_security_group_rule" "EC2SecurityGrouprule" {
  security_group_id        = "${aws_security_group.EC2SecurityGroup.id}"
  description = "Access to the RDS"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  type                     = "egress"
  source_security_group_id = "${aws_security_group.EC2SecurityGroup2.id}"
}

resource "aws_security_group_rule" "EC2SecurityGrouprule4" {
  security_group_id        = "${aws_security_group.EC2SecurityGroup.id}"
  description = "Access to the Secrets"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  type                     = "egress"
  source_security_group_id = "${aws_security_group.EC2SecurityGroup3.id}"
}

resource "aws_security_group" "EC2SecurityGroup2" {
    description = "Security group for the test RDS"
    name = "sgr-test-rds-prod"
    vpc_id = "${aws_vpc.EC2VPC.id}"
}

resource "aws_security_group_rule" "EC2SecurityGroup2rule" {
  security_group_id        = "${aws_security_group.EC2SecurityGroup2.id}"
  description = "Access from the AWS Lambda Function"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  type                     = "ingress"
  source_security_group_id = "${aws_security_group.EC2SecurityGroup.id}"
}

resource "aws_security_group" "EC2SecurityGroup3" {
    description = "Security group for the AWS Secrets Manager endpoint"
    name = "sgr-test-secrets-prod"
    vpc_id = "${aws_vpc.EC2VPC.id}"
}

resource "aws_security_group_rule" "EC2SecurityGroup3rule" {
  security_group_id        = "${aws_security_group.EC2SecurityGroup3.id}"
  description = "Access from the AWS Lambda Function"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  type                     = "ingress"
  source_security_group_id = "${aws_security_group.EC2SecurityGroup.id}"
}

#================================================================
# Lambda function
#================================================================

resource "aws_lambda_function" "LambdaFunction" {
    description = ""
    function_name = "test-lambda-function"
    handler = "lambda_function.lambda_handler"
    architectures = [
        "x86_64"
    ]
    s3_bucket = "${aws_s3_bucket.S3Bucket.bucket}"
    s3_key = "${aws_s3_bucket_object.LambdaFile.key}"
    memory_size = 128
    role = "${aws_iam_role.IAMRole.arn}"
    runtime = "python3.9"
    timeout = 600
    tracing_config {
        mode = "PassThrough"
    }
    vpc_config {
        subnet_ids = [
            "${aws_subnet.EC2Subnet.id}",
            "${aws_subnet.EC2Subnet2.id}"
        ]
        security_group_ids = [
            "${aws_security_group.EC2SecurityGroup.id}"
        ]
    }
    layers = [
        "${aws_lambda_layer_version.LambdaLayerVersion.arn}"
    ]
}

resource "aws_lambda_layer_version" "LambdaLayerVersion" {
    description = "Layer containing the psycopg2-binary for rotating PostgreSQL passwords"
    compatible_runtimes = [
        "python3.9"
    ]
    layer_name = "test-lambda-layer"
    s3_bucket = "${aws_s3_bucket.S3Bucket.bucket}"
    s3_key = "${aws_s3_bucket_object.LayerFile.key}"
}

resource "aws_lambda_permission" "LambdaPermission" {
    action = "lambda:InvokeFunction"
    function_name = "${aws_lambda_function.LambdaFunction.arn}"
    principal = "secretsmanager.amazonaws.com"
}

resource "aws_cloudwatch_log_group" "LogsLogGroup" {
    name = "/aws/lambda/${aws_lambda_function.LambdaFunction.function_name}"
}

#================================================================
# Amazon S3 objets
#================================================================

resource "aws_s3_bucket_object" "LayerFile" {
  bucket = "${aws_s3_bucket.S3Bucket.bucket}"
  key    = "python.zip"
  source = "python.zip"
}

resource "aws_s3_bucket_object" "LambdaFile" {
  bucket = "${aws_s3_bucket.S3Bucket.bucket}"
  key    = "lambda_function.zip"
  source = "lambda_function.zip"
}

#================================================================
# Amazon S3
#================================================================


resource "aws_s3_bucket" "S3Bucket" {
    bucket = "s3-test-us-east-1-rotation"
}

resource "aws_s3_bucket_acl" "S3BucketACL" {
  bucket = "${aws_s3_bucket.S3Bucket.id}"
  acl    = "private"
}

#================================================================
# Amazon RDS
#================================================================

resource "aws_db_instance" "RDSDBInstance" {
    identifier = "test-rds"
    allocated_storage = 20
    instance_class = "db.t3.micro"
    engine = "postgres"
    username = "test_user"
    password = "unsecure_passsword"
    name = "test_db"
    backup_window = "22:00-23:00"
    backup_retention_period = 7
    availability_zone = "us-east-1a"
    maintenance_window = "sat:08:00-sat:09:00"
    multi_az = false
    engine_version = "12.11"
    auto_minor_version_upgrade = true
    license_model = "postgresql-license"
    publicly_accessible = false
    storage_type = "gp2"
    port = 5432
    storage_encrypted = false
    copy_tags_to_snapshot = true
    monitoring_interval = 0
    iam_database_authentication_enabled = false
    deletion_protection = false
    skip_final_snapshot  = true # remove for production
    delete_automated_backups = true # remove for production
    db_subnet_group_name = "${aws_db_subnet_group.RDSDBSubnetGroup.name}"
    vpc_security_group_ids = [
        "${aws_security_group.EC2SecurityGroup2.id}"
    ]
    max_allocated_storage = 1000
}

resource "aws_db_parameter_group" "RDSDBParameterGroup" {
    name = "param-group-test-rds-prod"
    description = "Parameters group used by the test RDS"
    family = "postgres12"
    parameter {
        name = "log_connections"
        value = "1"
    }
    parameter {
        name = "log_disconnections"
        value = "1"
    }
    parameter {
        name = "max_connections"
        value = "LEAST({DBInstanceClassMemory/9531392},5000)"
    }
}

resource "aws_db_subnet_group" "RDSDBSubnetGroup" {
    description = "Subnets group for the RDS"
    name = "rds-subnet-group-test-prod"
    subnet_ids = [
        "${aws_subnet.EC2Subnet.id}",
        "${aws_subnet.EC2Subnet2.id}"
    ]
}

#================================================================
# Amazon VPC
#================================================================

resource "aws_vpc" "EC2VPC" {
    cidr_block = "10.3.0.0/16"
    enable_dns_support = true
    enable_dns_hostnames = true
    instance_tenancy = "default"

     tags = {
    Name = "vpc-test-production"
  }
}

resource "aws_vpc_endpoint" "EC2VPCEndpoint" {
    vpc_endpoint_type = "Gateway"
    vpc_id = "${aws_vpc.EC2VPC.id}"
    service_name = "com.amazonaws.us-east-1.s3"
    policy = "{\"Version\":\"2008-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":\"*\",\"Action\":\"*\",\"Resource\":\"*\"}]}"
    route_table_ids = [
         "${aws_route_table.EC2RouteTable.id}"
    ]
    private_dns_enabled = false
}

resource "aws_vpc_endpoint" "EC2VPCEndpoint2" {
    vpc_endpoint_type = "Interface"
    vpc_id = "${aws_vpc.EC2VPC.id}"
    service_name = "com.amazonaws.us-east-1.secretsmanager"
    policy = <<EOF
{
  "Statement": [
    {
      "Action": "*", 
      "Effect": "Allow", 
      "Principal": "*", 
      "Resource": "*"
    }
  ]
}
EOF
    subnet_ids = [
        "${aws_subnet.EC2Subnet.id}",
        "${aws_subnet.EC2Subnet2.id}"
    ]
    private_dns_enabled = true
    security_group_ids = [
        "${aws_security_group.EC2SecurityGroup3.id}"
    ]
}

resource "aws_subnet" "EC2Subnet" {
    availability_zone = "us-east-1c"
    cidr_block = "10.3.128.0/20"
    vpc_id = "${aws_vpc.EC2VPC.id}"
    map_public_ip_on_launch = false
}

resource "aws_subnet" "EC2Subnet2" {
    availability_zone = "us-east-1a"
    cidr_block = "10.3.144.0/20"
    vpc_id = "${aws_vpc.EC2VPC.id}"
    map_public_ip_on_launch = false
}

resource "aws_route_table" "EC2RouteTable" {
  vpc_id = "${aws_vpc.EC2VPC.id}"
    
  tags = {
    Name = "rtb-test"
  }
}

#================================================================
# Amazon IAM
#================================================================

resource "aws_iam_role_policy" "IAMManagedPolicy" {
    name = "rotate-secrets"
    role = aws_iam_role.IAMRole.id
    policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "secretsmanager:DescribeSecret",
                "secretsmanager:GetSecretValue",
                "secretsmanager:PutSecretValue",
                "secretsmanager:UpdateSecretVersionStage"
            ],
            "Resource": "${aws_secretsmanager_secret.SecretsManagerSecret.arn}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "secretsmanager:GetRandomPassword"
            ],
            "Resource": "*"
        },
        {
            "Action": [
                "ec2:CreateNetworkInterface",
                "ec2:DeleteNetworkInterface",
                "ec2:DescribeNetworkInterfaces",
                "ec2:DetachNetworkInterface"
            ],
            "Resource": "*",
            "Effect": "Allow"
        }
    ]
}
EOF
}

resource "aws_iam_role_policy" "IAMManagedPolicy2" {
    name = "AWSLambdaBasicExecutionRole"
    role = aws_iam_role.IAMRole.id
    policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "logs:CreateLogGroup",
            "Resource": "arn:aws:logs:us-east-1:*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": [
                "${aws_lambda_function.LambdaFunction.arn}"
            ]
        }
    ]
}
EOF
}

resource "aws_iam_role" "IAMRole" {
    path = "/service-role/"
    name = "test-rotation-role"
    assume_role_policy = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"lambda.amazonaws.com\"},\"Action\":\"sts:AssumeRole\"}]}"
    max_session_duration = 3600
}

#================================================================
# AWS Secrets Manager
#================================================================

resource "aws_secretsmanager_secret" "SecretsManagerSecret" {
    name = "test-secret-rotation-prod"
    description = "Secret for storing the RDS test params"
}

resource "aws_secretsmanager_secret_version" "SecretsManagerSecretVersion" {
    secret_id = "${aws_secretsmanager_secret.SecretsManagerSecret.id}"
    secret_string = "{\"DB_PASSWORD\": \"unsecure_passsword\", \"DB_NAME\": \"test_db\", \"DB_USER\": \"test_user\", \"DB_HOST\": \"${aws_db_instance.RDSDBInstance.address}\", \"DB_PORT\": \"5432\", \"DB_ENGINE\": \"postgres\"}"
}

resource "aws_secretsmanager_secret_rotation" "SecretsManagerSecretRotationScheduler" {
  secret_id = "${aws_secretsmanager_secret.SecretsManagerSecret.id}"
  rotation_lambda_arn = "${aws_lambda_function.LambdaFunction.arn}"
  rotation_rules {
    automatically_after_days = 30
  }
}