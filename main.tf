provider "aws" {
  region = "eu-west-2"

  # Make it faster by skipping something
  skip_get_ec2_platforms      = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  skip_credentials_validation = true
  skip_requesting_account_id  = true
}

# EventBridge rule and targets
module "eventbridge" {
  source  = "terraform-aws-modules/eventbridge/aws"
  version = "1.14.0"

  create_bus = false

  rules = {
    crons = {
      description         = "Trigger for a Lambda"
      schedule_expression = "cron(0 20 * * ? *)"
    }
  }

  targets = {
    crons = [
      {
        name  = "lambda_autoscaling"
        arn   = aws_lambda_function.lambda.arn
        role_name = aws_iam_role.iam_for_lambda_autoscaling.name
        input = jsonencode({ "job" : "cron-by-rate" })
      },
      {
        name = "log-orders-to-cloudwatch"
        arn  = aws_cloudwatch_log_group.log_group.arn
        role_name = aws_iam_role.iam_for_lambda_autoscaling.name
      }
    ]
  }
}

# Cloudwatch Log Group
resource "aws_cloudwatch_log_group" "log_group" {
  name              = "/aws/lambda/lambda_autoscaling"
  retention_in_days = 14
}

# Lambda function, permission, role and policies
data "archive_file" "zip" {
  type        = "zip"
  source_file = "${path.module}/python/lambda_autoscaling.py"
  output_path = "${path.module}/python/lambda_autoscaling.zip"
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = module.eventbridge.eventbridge_rule_arns["crons"]
}

data "aws_iam_policy_document" "policy" {
  statement {
    sid    = ""
    effect = "Allow"

    principals {
      identifiers = ["lambda.amazonaws.com"]
      type        = "Service"
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "iam_for_lambda_autoscaling" {
  name               = "iam_for_lambda_autoscaling"
  assume_role_policy = data.aws_iam_policy_document.policy.json
}

resource "aws_iam_role_policy_attachment" "role-policy-attachment" {
  for_each = toset([
    "arn:aws:iam::889605739882:policy/service-role/AWSLambdaBasicExecutionRole-b11f14a3-9353-44dc-948d-ae0a3725f5d6",
    "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess",
    "arn:aws:iam::889605739882:policy/AmazonEKSClusterAutoscalerPolicy",
    "arn:aws:iam::889605739882:policy/lambda-autoscaling-policy"
  ])
  role       = aws_iam_role.iam_for_lambda_autoscaling.name
  policy_arn = each.value
}

resource "aws_lambda_function" "lambda" {
  function_name = "lambda_autoscaling"

  filename         = "${path.module}/python/lambda_autoscaling.zip"
  source_code_hash = data.archive_file.zip.output_base64sha256
  role             = aws_iam_role.iam_for_lambda_autoscaling.arn
  handler          = "lambda_autoscaling.lambda_handler"
  runtime          = "python3.6"

  depends_on = [
    aws_cloudwatch_log_group.log_group
  ]

  # Variables passed to the lambda function
  environment {
    variables = {
      asg_name = "eks-node-group-cloudnative-poc-42beabc6-9384-ecef-28ee-cee4f0b02f4c"
      min = 1
      max = 30
      desired = 7
    }
  }
}
