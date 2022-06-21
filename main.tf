provider "aws" {
  region = "eu-west-2"

  # Make it faster by skipping something
  skip_get_ec2_platforms      = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  skip_credentials_validation = true
  skip_requesting_account_id  = true
}

module "eventbridge" {
  source  = "terraform-aws-modules/eventbridge/aws"
  version = "1.14.0"

  create_bus = false

  rules = {
    crons = {
      description         = "Trigger for a Lambda"
      schedule_expression = "rate(2 minutes)"
    }
  }

  targets = {
    crons = [
      {
        name  = "hello_lambda_test"
        arn   = aws_lambda_function.lambda.arn
        role_name = aws_iam_role.iam_for_lambda_test.name
        input = jsonencode({ "job" : "cron-by-rate" })
      },
      {
        name = "log-orders-to-cloudwatch"
        arn  = aws_cloudwatch_log_group.log_group.arn
        role_name = aws_iam_role.iam_for_lambda_test.name
      }
    ]
  }
}

data "archive_file" "zip" {
  type        = "zip"
  source_file = "${path.module}/python/hello_lambda.py"
  output_path = "${path.module}/python/hello_lambda.zip"
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

resource "aws_iam_role" "iam_for_lambda_test" {
  name               = "iam_for_lambda_test"
  assume_role_policy = data.aws_iam_policy_document.policy.json
}

resource "aws_iam_role_policy_attachment" "role-policy-attachment" {
  for_each = toset([
    "arn:aws:iam::889605739882:policy/service-role/AWSLambdaBasicExecutionRole-b11f14a3-9353-44dc-948d-ae0a3725f5d6",
    "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess",
    "arn:aws:iam::889605739882:policy/AmazonEKSClusterAutoscalerPolicy"
  ])
  role       = aws_iam_role.iam_for_lambda_test.name
  policy_arn = each.value
}

resource "aws_cloudwatch_log_group" "log_group" {
  name              = "/aws/lambda/hello_lambda_test"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_stream" "lambda_stream" {
  name           = "hello_lambda_stream"
  log_group_name = aws_cloudwatch_log_group.log_group.name
}

resource "aws_lambda_function" "lambda" {
  function_name = "hello_lambda_test"

  filename         = "${path.module}/python/hello_lambda.zip"
  source_code_hash = data.archive_file.zip.output_base64sha256
  role             = aws_iam_role.iam_for_lambda_test.arn
  handler          = "hello_lambda.lambda_handler"
  runtime          = "python3.6"

  depends_on = [
    aws_cloudwatch_log_group.log_group
  ]

  environment {
    variables = {
      greeting = "Hello"
    }
  }
}
