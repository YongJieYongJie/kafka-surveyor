#!/usr/bin/env bash

# gitReposPath is the common base path for all git repositories. It will be
# used to search for source files containing code that publishes to particular
# environment variables that represent Kafka topics.
gitReposPath='/**/path-to-my-git-repos'

# devopsGitRepoPath is the path to the repository containing the build scripts
# for the services. It is assumed that the services are deployment using
# Ansible scripts, with a <service-name>.yml for each service, and the YAML
# file contains lines like `MY_BEAUTIFUL_TOPIC_NAME_ENV_VAR:
# my-actual-template-{{ env }}-topic-name`, which will be used when searching
# for grepping on either the environment variable or the template string, to
# get the other.
devopsGitRepoPath="$gitReposPath/DEVOPS"

# replaceProdWithTemplateString converts
# "my-consumer-group-production-1-sg" to
# "my-consumer-group-[^-]*-1-[^-]*" for use in ripgrep in
# order to locate the name of the environment variables used to store the
# actual Kafka consumer group ID. This is necessary because the actual consumer
# group IDs on Kafka are constructed by Ansible using templating.
# 
# Also replaces the various system IDs: like -sg | -my, to: -[^-]*.
function replaceProdWithTemplateString(){
  sed -e 's/production/[^-]*/' -e 's/-sg\|-my/-[^-]*/'
}

function consumerGroupIDToEnvVar(){
  while read consumerGroupID
  do
    echo "[*] Locating service for consumer group ID: $consumerGroupID"
    consumerGroupIDTemplate=$(echo $consumerGroupID | replaceProdWithTemplateString)
    rg --no-heading --files-with-matches "$consumerGroupIDTemplate" $devopsGitRepoPath
  done
}

kafka-consumer-groups.sh --bootstrap-server $KAFKA_BOOTSTRAP_SERVER --list \
  | consumerGroupIDToEnvVar

