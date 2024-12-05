provider "aws" {
  region = var.aws_region
}

resource "aws_vpc" "main" {
  count      = var.create_vpc ? 1 : 0
  cidr_block = var.vpc_cidr
  tags       = { Name = "Main-VPC" }
}

resource "aws_subnet" "main" {
  count             = var.create_vpc ? 1 : 0
  vpc_id            = aws_vpc.main[0].id
  cidr_block        = var.subnet_cidr
  availability_zone = var.availability_zone
  tags              = { Name = "Main-Subnet" }
}

resource "aws_instance" "main" {
  count         = var.create_ec2 ? 1 : 0
  ami           = var.ami_id
  instance_type = var.instance_type
  subnet_id     = var.create_vpc ? aws_subnet.main[0].id : var.subnet_id
  key_name      = var.key_pair_name
  tags          = { Name = "Main-EC2" }
}

resource "random_id" "bucket_suffix" {
  count       = var.create_s3 ? 1 : 0
  byte_length = 8
}

resource "aws_s3_bucket" "main" {
  count  = var.create_s3 ? 1 : 0
  bucket = "${var.s3_bucket_name}-${random_id.bucket_suffix[0].hex}"
  tags   = { Name = "Main-S3" }
}

resource "aws_launch_template" "main" {
  count          = var.create_autoscaling ? 1 : 0
  name           = "asg-launch-template"
  image_id       = var.ami_id
  instance_type  = var.instance_type
  key_name       = var.key_pair_name
  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "ASG-Instance" }
  }
}

resource "aws_autoscaling_group" "main" {
  count             = var.create_autoscaling ? 1 : 0
  desired_capacity  = var.autoscaling_desired_capacity
  max_size          = var.autoscaling_max_size
  min_size          = var.autoscaling_min_size

  launch_template {
    id      = aws_launch_template.main[0].id
    version = "$Latest"
  }

  vpc_zone_identifier = var.create_vpc ? [aws_subnet.main[0].id] : [var.subnet_id]
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_execution_role" {
  name               = "lambda_execution_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

# Upload Lambda Code to S3
resource "aws_s3_bucket_object" "lambda_code" {
  count      = var.create_lambda ? 1 : 0
  bucket     = aws_s3_bucket.main[0].bucket
  key        = "lambda-code.zip"
  source     = "path/to/your/lambda-code.zip"  # Path to the local Lambda code zip file
  acl        = "private"
}

# Lambda Function
resource "aws_lambda_function" "main" {
  count           = var.create_lambda ? 1 : 0
  function_name   = "MyLambdaFunction"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "index.handler"  # Adjust this depending on your Lambda function's entry point
  runtime         = "nodejs14.x"  # Adjust the runtime based on your Lambda code
  s3_bucket       = aws_s3_bucket.main[0].bucket
  s3_key          = "lambda-code.zip"  # The S3 key where the Lambda function code is stored
  timeout         = 15
  memory_size     = 128
  environment {
    variables = {
      key = "value"  # Environment variables for your Lambda function
    }
  }
}

# Optional: Attach additional IAM policies to Lambda Execution Role (if needed)
resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda-policy"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "s3:GetObject"
        Effect   = "Allow"
        Resource = "arn:aws:s3:::${aws_s3_bucket.main[0].bucket}/*"
      },
      {
        Action   = "logs:*"
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}
