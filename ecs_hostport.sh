
#!/bin/bash

# This script returns the IP and port number of the instance running a task
# of a service on and ECS cluster.

set -eu

if [ $# -lt 6 ] ; then
    echo "Usage: $0 [--service service] [--region region] [--cluster cluster]"
    exit
fi


# assign keyword args
while true; do 
  case "${1:-}" in
    --service)
      SERVICE="$2"
      shift 2
      ;;
    --region)
      REGION="$2"
      shift 2
      ;;
    --cluster)
      CLUSTER="$2"
      shift 2
      ;;
    *)
      break
      ;;
  esac
done


# ECS calls

# 1. make call to get first arn of running task by service name
taskArn=$(aws ecs list-tasks --cluster $CLUSTER --service-name $SERVICE | jq ".taskArns[0]" | tr -d '"') 2> /dev/null

# 2. make call to get metadata about a task
_tasks=$(aws ecs describe-tasks --cluster $CLUSTER --tasks $taskArn) 2> /dev/null
# strip port and instance arn from previous call
taskPort=$(echo $_tasks | jq ".tasks[0].containers[0].networkBindings[0].hostPort" | tr -d '"') 
instanceArn=$(echo $_tasks | jq ".tasks[0].containerInstanceArn" | tr -d '"')

# 3. make call to get instance id of EC2 instance the task is running on
instanceId=$(aws ecs describe-container-instances --cluster $CLUSTER --container-instances $instanceArn | jq ".containerInstances[0].ec2InstanceId" | tr -d '"') 2> /dev/null

# EC2 calls

# 4. make call to get the private id of the EC2 instance the task is running on
instancePrivateIp=$(aws ec2 describe-instances --instance-ids $instanceId | jq ".Reservations[0].Instances[0].PrivateIpAddress" | tr -d '"') 2> /dev/null



echo "$instancePrivateIp:$taskPort"

