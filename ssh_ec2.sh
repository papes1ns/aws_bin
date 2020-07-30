#!/bin/bash

# This script will allow to SSH an instance that is running a ECS task of a
# the service passed in to the script.

set -eu  # do not proceed on error

if [ $1 = "help" ] || [ $1 = "-h" ] ; then
  cat <<EOF
echo "Usage: $0 [--profile profile] [--region region] [--key key] [--user user] [--port port] [--ip-type public|private] [--ip ip] [cluster] [service]"
--profile          aws profile, defaults to 'default'
--region           aws region, defaults to 'us-east-1'
--key              private key for ssh connection
--user             login name for ssh connection, defaults to current shell user
--port             port for ssh connection
--ip-type          connect to host with 'public' or 'private' IP
--ip               pass in ip to avoid doing cluster and service lookup
cluster
  pass in the cluster to avoid prompt
  
service
  pass in service name to avoid prompt
EOF
  exit
fi

# assign keyword args
while true; do
  case ${1:-} in
    --profile)
      profile="$2"
      shift 2
      ;;
    --region)
      region="$2"
      shift 2
      ;;
    --key)
      key="$2"
      shift 2
      ;;
    --user)
      user="$2"
      shift 2
      ;;
    --port)
      port="$2"
      shift 2
      ;;
    --ip)
      ip="$2"
      shift 2
      ;;
    --ip-type)
      ipType="$2"
      shift 2
      ;;
    *)
      break
      ;;
  esac
done

# assign defaults for optional args
cluster="${cluster:-}"
service="${service:-}"
region="${region:-us-east-1}"
profile="${profile:-default}"
key="${key:-}"
user="${user:-$(whoami)}"
port="${port:-22}"
ip="${ip:-}"
ipType="${ipType:-private}"

# aws getter functions

function getTaskArn() {
  # $1: cluster
  # $2: service name
  aws ecs list-tasks --region $region --profile $profile --cluster $1 --service-name $2  | jq ".taskArns[0]"
}

function getContainerInstanceArn() {
  # $1: cluster
  # $2: task arn
  aws ecs describe-tasks --region $region --profile $profile --cluster $1 --tasks [$2] | jq ".tasks[0].containerInstanceArn"
}

function getEc2InstanceId() {
  # $1: cluster
  # $2: container instance arn
  aws ecs describe-container-instances --region $region --profile $profile --cluster $1 --container-instances [$2] | jq ".containerInstances[0].ec2InstanceId"
}

function getEc2InstanceIp() {
  # $1: instance id
  ipAttr=$([ $ipType = "private" ] && echo 'PrivateIpAddress' || echo 'PublicIpAddress')
  aws ec2 describe-instances --region $region --profile $profile --instance-ids [$1] | jq ".Reservations[0].Instances[0].$ipAttr" | tr -d '"'
}

function getClusterArns() {
  aws ecs list-clusters --region $region --profile $profile | jq ".clusterArns[]" | tr -d '"'
}

function getServiceArns() {
  # $1: cluster
  aws ecs list-services --region $region --profile $profile --cluster $cluster | jq ".serviceArns[]" | tr -d '"'
}

# end aws getter functions


# if ip is passed in we do not need to do lookups on cluster or service
if [ ! -z $ip ]; then
  echo "ip passed in.. skipping service lookup"
  taskEc2InstanceIp=$ip
else
  # if cluster or server name are not passed in show the user their options

  if [ -z $cluster ]; then
    clusters=($(getClusterArns $cluster))
    echo
    echo
    echo "===== clusters ====="
    for i in "${clusters[@]}"
    do
       echo ${i##*/}
    done
    echo
    echo
    echo "please input a cluster name"
    read cluster
    echo "using: $cluster"
  fi

  if [ -z $service ]; then
    services=($(getServiceArns $cluster))
    echo
    echo
    echo "===== services ====="
    for i in "${services[@]}"
    do
       echo ${i##*/}
    done
    echo
    echo
    echo "please input a service name"
    read service
    echo "using: $service"
  fi

  # should have all the information we need at this point to get an ip address of
  # ec2 instance running a task for $service inside #cluster

  taskArn="$(getTaskArn $cluster $service)"
  taskContainerInstanceArn="$(getContainerInstanceArn $cluster $taskArn)"
  taskEc2InstanceId="$(getEc2InstanceId $cluster $taskContainerInstanceArn )"
  taskEc2InstanceIp="$(getEc2InstanceIp $taskEc2InstanceId)"
fi

if [ ! -z $key ]; then
  key="-i $key"
fi

echo "ssh $key $user@$taskEc2InstanceIp -p $port"

ssh $key $user@$taskEc2InstanceIp -p $port