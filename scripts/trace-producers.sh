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



########################
# Function Definitions #
########################

# grepEnvVar reads a stream of environment variables representing Kafka topcis,
# and for each environment variable, the function uses ripgrep to search for
# Java source files that calls the ".publish()" method on the environment
# variable.
function grepEnvVar(){
  while read envVar
  do
    echo "  [+] Locating files publishing to: $envVar"
    rg --type java --files-with-matches $envVar $gitReposPath --glob !'DEVOPS' \
      | \
      while read filepath
      do
        rg --multiline --multiline-dotall 'publish\([^)]*?'$envVar $filepath \
          && echo "    [!] Found file containing $envVar: $filepath"
      done
    done
}

# replaceProdWithTemplateString converts
# "my-production-topic-for-sg" to
# "my-[^-]*-topic-for-[^-]*" for use in ripgrep in order
# to locate the name of the environment variables used to store the actual
# Kafka topics. This is necessary because the actual topic names on Kafka are
# constructed by Ansible using templating.
function replaceProdWithTemplateString(){
  sed -e 's/production/[^-]*/' -e 's/-sg\|-my/-[^-]*/'
}

function trimLeadingSpaces(){
  sed -e 's/^  *//'
}

function extractFirstFieldLeftOfColon(){
  cut --field 1 --delimiter ':'
}

function findProducersByTopic(){
  while read topic
  do
    echo "[*] Searching for producers to topic: $topic"
    topicTemplate=$(echo $topic | replaceProdWithTemplateString)
    rg --no-heading --no-filename "$topicTemplate" $devopsGitRepoPath \
      | trimLeadingSpaces \
      | extractFirstFieldLeftOfColon \
      | uniq \
      | grepEnvVar
    done
  }


########
# MAIN #
########

kafka-topics.sh --bootstrap-server $KAFKA_BOOTSTRAP_SERVER --list \
  | findProducersByTopic
