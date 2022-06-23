provider "aws" {
  region = "eu-west-1"

  # Make it faster by skipping something
  skip_get_ec2_platforms      = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  skip_credentials_validation = true
  skip_requesting_account_id  = true
}

# EventBridge rules and targets
module "eventbridge" {
  source  = "terraform-aws-modules/eventbridge/aws"
  version = "1.14.0"

  create_bus = false

  rules = {
    cron-scale-down = {
      description         = "Trigger for a Lambda to scale down"
      schedule_expression = "cron(0 20 * * ? *)"
    },
    cron-scale-up = {
      description         = "Trigger for a Lambda to scale up"
      schedule_expression = "cron(0 7 * * ? *)"
    }
  }

  targets = {
    # Pass input: 'asg_name', 'min', 'max' and 'desired' variables to lambda function
    cron-scale-down = [
      {
        name  = "lambda_autoscaling"
        arn   = aws_lambda_function.lambda.arn
        role_name = aws_iam_role.iam_for_lambda_autoscaling.name
        input = jsonencode({ "job" : "cron-by-rate","asg_name" : "eks-dea-01-general-220220526073619074400000017-6ac07fa5-bf53-3b68-1a34-38bc296b69f0", "min" : "1", "max" : "14", "desired" : "1"})
      },
      {
        name = "log-orders-to-cloudwatch"
        arn  = aws_cloudwatch_log_group.log_group.arn
        role_name = aws_iam_role.iam_for_lambda_autoscaling.name
      }
    ]
    cron-scale-up = [
      {
        name  = "lambda_autoscaling2"
        arn   = aws_lambda_function.lambda.arn
        role_name = aws_iam_role.iam_for_lambda_autoscaling.name
        input = jsonencode({ "job" : "cron-by-rate", "asg_name" : "eks-dea-01-general-220220526073619074400000017-6ac07fa5-bf53-3b68-1a34-38bc296b69f0","min" : "1","max" : "16","desired" : "1" })
      },
      {
        name = "log-orders-to-cloudwatch2"
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

# change role name for different region
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
  kms_key_arn      = aws_kms_key.a.arn

  depends_on = [
    aws_cloudwatch_log_group.log_group
  ]

  # Variables passed to the lambda function
  # environment {
  #   variables = {
  #     # change autoscaling group name for region
  #     asg_name = "eks-dea-01-general-220220526073619074400000017-6ac07fa5-bf53-3b68-1a34-38bc296b69f0"
  #     min = 1
  #     max = 15
  #     desired = 1
  #   }
  # }
}

# Permission to invoke lmabda function
resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = module.eventbridge.eventbridge_rule_arns["cron-scale-down"]
}
resource "aws_lambda_permission" "allow_cloudwatch2" {
  statement_id  = "AllowExecutionFromCloudWatch2"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = module.eventbridge.eventbridge_rule_arns["cron-scale-up"]
}

# Create kms key for lambda
resource "aws_kms_key" "a" {
  description             = "KMS key eu-west-1"
  deletion_window_in_days = 10
}