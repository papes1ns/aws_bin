#!/bin/bash

# This script will connect you to an ec2 instance in a private subnet given there
# is a VPN tunnel on local network to an AWS VPC. This script is built to find
# a bastion instance and connect using ec2-instance-connect and jump to destination
# from there.
#
# This script is meant to be used in an .ssh/config. See below for an example:
#
#  Host 172.24.*
#    ProxyCommand ssh_proxy.sh --profile default --region us-east-1 --cluster production %r %h %p
#
#

set -eu

if [ $# -lt 2 ] ; then
    echo "Usage: $0 [--profile profile] [--region region] [--cluster cluster] [--bastion-name bastion-name] user host [port] [local_port]"
    exit
fi

# assign keyword args
while true; do
  case $1 in
    --profile)
      PROFILE="--profile $2"
      shift 2
      ;;
    --region)
      REGION="--region $2"
      shift 2
      ;;
    --cluster)
      CLUSTER=$2
      shift 2
      ;;
    --bastion-name)
      BASTION_NAME=$2
      shift 2
      ;;
    *)
      break
      ;;
  esac
done


# assign positional args
LOCAL_PORT="${4:-}"
PORT="${3:-22}"
BASTION_NAME="${BASTION_NAME:-bastion}"
LOGIN=$1
DESTHOST=$2

# find the data on the bastion host for this cluster
read -r instance_id availability_zone private_ip <<< $( \
  aws ec2 describe-instances $PROFILE $REGION \
    --filter "Name=tag:Name,Values=$BASTION_NAME" \
    --query 'Reservations[*].Instances[*].[InstanceId,Placement.AvailabilityZone,PrivateIpAddress]' \
    --output text \
    2> /dev/null \
)


# generate one-time RSA key
scriptpath="$( cd "$(dirname "$0")" ; pwd -P )"
private_key="$scriptpath/ephemeralkey"
public_key="$scriptpath/ephemeralkey.pub"
rm -f $private_key
rm -f $public_key
ssh-keygen -t rsa -f $private_key -N ""

# send one-time RSA key to bastion host
aws ec2-instance-connect send-ssh-public-key $REGION $PROFILE \
  --instance-id $instance_id \
  --availability-zone $availability_zone \
  --ssh-public-key file://$public_key \
  --instance-os-user ec2-user \
  2> /dev/null

flags=()

flags+=("-F /dev/null")      # do not use directives from ~/.ssh/config
flags+=("-i $private_key")   # use one-time key

# check to see if there is a local port to forward to; otherwise create a tunnel
# to the destination
if [ -n "$LOCAL_PORT" ]; then
  flags+=("-N")   # do not drop a shell when forwarding ports
  flags+=("-L $LOCAL_PORT:$DESTHOST:$PORT")  # forward ports
else
  if [ "$private_ip" != "$DESTHOST" ]; then
    flags+=("-W $DESTHOST:$PORT")  # create tunnel with destination
  fi
fi

flags_str=$(IFS=' '; echo "${flags[*]}" ) # join array of flags separated by space

cmd="ssh $flags_str ec2-user@$private_ip"
echo "$cmd"

ssh $flags_str ec2-user@$private_ip