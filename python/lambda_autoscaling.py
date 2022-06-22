import boto3
import os
# Boto Connection

def lambda_handler(event, context):
  print(event)
  asg = boto3.client('autoscaling',os.environ['AWS_REGION'])
  response = asg.update_auto_scaling_group(AutoScalingGroupName=os.environ['asg_name'],MinSize=int(os.environ['min']),DesiredCapacity=int(os.environ['desired']),MaxSize=int(os.environ['max']))
  print(response)
