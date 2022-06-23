# Cloudwatch EventBridge Lambda & Scheduled Events Example

The configuration in this repository will create 2 EventBridge scheduled rules, that trigger a Lambda function to scale down/scale up a specific autoscaling group. It also creates a Cloudwatch log group to visualise the lambda function logs.
## Usage
To run this example you need to execute:
```
terraform init
terraform plan
terraform apply
```

Note that this example may create resources which cost money. Run ```terraform destroy``` when you don't need these resources.

## Requirements
| Name          | Versions      |
| ------------- |:-------------:|
| terraform     | >= 0.13.1.    |
| aws           | >= 3.44       |
| null          | >= 2.0        |
| random        | >= 3.0        |

## Providers
| Name          | Versions      |
| ------------- |:-------------:|
| null          | >= 2.0        |
| random        | >= 3.0        |

## EventBridge Setup
The configuration will create two EventBridge rules with scheduled expressions to trigger the specified lambda function everyday at 07:00 and 20:00 UTC. Both rules pass different inputs to the lambda function and so the 07:00 rule will scale up the declared autoscaling group while the 20:00 rule will scale down the autoscaling group. The EventBridge targets point to the lambda function and the desired CloudWatch log group.
```
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
```
## CloudWatch Setup
Create a Cloudwatch log group to monitor the lambda function
```
resource "aws_cloudwatch_log_group" "log_group" {
  name              = "/aws/lambda/lambda_autoscaling"
  retention_in_days = 14
}
```
## Lambda Function
This configuration is needed to zip the Lambda function's python script.
```
data "archive_file" "zip" {
  type        = "zip"
  source_file = "${path.module}/python/lambda_autoscaling.py"
  output_path = "${path.module}/python/lambda_autoscaling.zip"
}
```
Create a role and attach any policies needed to perform the tasks
```
resource "aws_iam_role" "iam_for_lambda_autoscaling" {
  name               = "iam_for_lambda_autoscaling"
  assume_role_policy = data.aws_iam_policy_document.policy.json
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
```
Create the Lambda function resource configuring correctly the ```filename```, ```source_code_hash```, ```role```, ```handler``` and ```runtime```. The environment variables are passed into the lambda function and dictate how to scale the declared AutoScaling Group. The ```depends_on``` section is added to emphasise that the lambda logs should be directed to the ```log_group``` created above.
```
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

  # Variables can be passed to the lambda function here or see the targets input
  environment {
    variables = {
      asg_name = "eks-node-group-cloudnative-poc-42beabc6-9384-ecef-28ee-cee4f0b02f4c"
      min = 1
      max = 30
      desired = 7
    }
  }
}
```
## Permissions
Finally, add an ```aws_lambda_permission``` resource to allow cloudwatch to invoke the lambda function using the EventBridge rule's schedules.
```
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
```
