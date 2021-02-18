#!/usr/bin/env bash

# getKubeApps uses kubectl to retrieve a list of app names on the Kubernetes
# cluster, by listing each unique label `app=<retrieved-app-name>`.
function getKubeApps() {
  kubectl get pods --output custom-columns="APP:.metadata.labels.app" \
    | sed --quiet --expression '2,$p' | sort | uniq
  }

# getPodIPs accepts app names from STDIN, and for each app name, uses kubectl
# list all the # the IPs of all pods with the label `app=<app-name>`.
function getPodIPs() {
  appLabel=$1
  kubectl get pods --selector="app=$appLabel" \
    --output custom-columns="IP:.status.podIP" 2> /dev/null \
    | sed --quiet --expression '2,$p' \
    | while read podIP
    do
      echo "$appLabel|$podIP"
    done
}

# getOutputKafkaTopics accepts IP address from STDIN (in the format
# "<app-name>|<ip-address>", and for each IP address, uses Jmxterm to query for
# mbeans that shows that topics being produced to.
function getOutputKafkaTopics() {
  echo 'beans' > jmxterm-commands.tmp
  while read appNameAndPodIP
  do
    # Note: The `#` operator operates on the string provided on the left (in
    # this case $appNameAndPodIP), removing from it the shortest prefix
    # matching the pattern provided on the right (in this case: "*|")
    podIP=${appNameAndPodIP#*|}

    # Note: The `%` operator operates on the string provided on the left (in
    # this case $appNameAndPodIP), removing from it the shortest suffix
    # matching the pattern provided on the right (in this case: "*|")
    appName=${appNameAndPodIP%|*}

    java -jar jmxterm-1.0.2-uber.jar --noninteract --verbose silent \
      --url "$podIP:9010" --input jmxterm-commands.tmp 2> /dev/null \
      | grep producer-topic-metrics \
      | cut --delimiter ',' --fields 2 \
      | cut --delimiter '=' --fields 2 \
      | while read topicName
        do
          echo "$appName|$topicName"
        done
  done | sort | uniq
  rm -f jmxterm-commands.tmp || true
}


# echoAsJSON accepts app name and topic name from STDIN (in the format
# "<app-name>|<topic-name>"), and outputs the corresponding JSON line:
# "  {\"source\": \"<app-name>\", \"target\": \"<topic-name>\", \"type\": \"producing\" },".
function echoAsJSON() {
  while read appNameAndTopicName
  do
    appName=${appNameAndTopicName#*|}
    topicName=${appNameAndTopicName%|*}
    echo "  { \"source\": \"$appName\", \"target\": \"$topicName\", \"type\": \"producing\" },"
  done
}

# ಠ_ಠ is the main function where all the ✨magic✨ happens.
function ಠ_ಠ() {
  echo '['
  getKubeApps \
    | while read appLabel
      do
        getPodIPs $appLabel | getOutputKafkaTopics | echoAsJSON
      done 
  echo ']'
}

ಠ_ಠ

