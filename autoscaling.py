import os
import boto3

client = boto3.client('autoscaling')

def get_env_variable(var_name):
    msg = "Set the %s environment variable"
    try:
        return os.environ[var_name]
    except KeyError:
        error_msg = msg % var_name

def lambda_handler(event, context):
    auto_scaling_groups = get_env_variable('eks-node-group-cloudnative-poc-42beabc6-9384-ecef-28ee-cee4f0b02f4c').split()

    for group in auto_scaling_groups:
        if servers_need_to_be_started(group):
            action = "Starting"
            min_size = int(get_env_variable('1'))
            max_size = int(get_env_variable('30'))
            desired_capacity = int(get_env_variable('6'))
        else:
            action = "Stopping"
            min_size = 0
            max_size = 0
            desired_capacity = 0

        print (action + ": " + group)
        response = client.update_auto_scaling_group(
            AutoScalingGroupName=group,
            MinSize=min_size,
            MaxSize=max_size,
            DesiredCapacity=desired_capacity,
        )

        print (response)

def servers_need_to_be_started(group_name):
    min_group_size = get_current_min_group_size(group_name)
    if min_group_size == 0:
        return True
    else:
        return False

def get_current_min_group_size(group_name):
    response = client.describe_auto_scaling_groups(
        AutoScalingGroupNames=[ group_name ],
    )
    return response["AutoScalingGroups"][0]["MinSize"]