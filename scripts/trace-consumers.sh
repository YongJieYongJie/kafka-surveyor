#!/usr/bin/env bash

#################
# Documentation #
#################

# This script generate outputs that looks like the following:
#
# [Subscribed Topic(s) for Consumer Group: my-consumer-group-prod-1]
# my-beautiful-prod-topic-1
# [Subscribed Topic(s) for Consumer Group: my-consumer-group-prod-2]
# my-beautiful-prod-topic-2
# [Subscribed Topic(s) for Consumer Group: my-consumer-group-prod-3]
# my-beautiful-prod-topic-3
# my-beautiful-prod-topic-4


##################
# Pre-conditions #
##################

# Ensure that the environment variable KAFKA_BOOTSTRAP_SERVER is set.
# Ensure that kafka-consumer-groups.sh is available on PATH.


########################
# Function Definitions #
########################

remove_headers() {
  sed 1,2d
}

filter_topic_column() {
  cut -f2 -d' '
}

remove_duplicates() {
  sort | uniq
}

list_subscribed_topics() {
  while read kafka_consumer_group_id
  do
    echo "[Subscribed Topic(s) for Consumer Group: $kafka_consumer_group_id]"
    kafka-consumer-groups.sh \
      --bootstrap-server $KAFKA_BOOTSTRAP_SERVER \
      --group $kafka_consumer_group_id \
      --describe \
      | remove_headers | filter_topic_column | remove_duplicates
    done
  }

list_consumer_group_ids() {
  kafka-consumer-groups.sh --bootstrap-server $KAFKA_BOOTSTRAP_SERVER --list
}


########
# Main #
########

list_consumer_group_ids  | list_subscribed_topics
