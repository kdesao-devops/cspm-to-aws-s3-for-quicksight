#!/bin/bash

# To use a command line as a data module, terraform require a script to execute and can't be used as simple command line.

#Checting if the variable exist
if [ -z "$1" ]; then exit 1; else region=$1; fi
if [ -z "$2" ]; then exit 1; else account_id=$2; fi

# Requestion and parsing the user arn
arn=`aws quicksight list-users --region $1 --aws-account-id $2 --namespace default --output text --query 'UserList[0].Arn'`

#Creating a json output
jq -n \
    --arg arn "$arn" \
    '{"arn":$arn}'