#!/usr/bin/env bash

#################
# Documentation #
#################

# This script generate outputs that looks like the following:
#
#  [
#    { "source": "source-topic-name", "target": "subscribing-consumer-group-id" },
#    { "source": "source-topic-name", "target": "subscribing-consumer-group-id" },
#    { "source": "source-topic-name", "target": "subscribing-consumer-group-id" },
#    { "source": "source-topic-name", "target": "subscribing-consumer-group-id" },
#  ]


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

# echo_as_source_target_javascript_object reads from STDIN the name of topic,
# AND ALSO TAKES AS ARGUMENT the name of the subscribing consumer group ID, and
# outputs lines that look like this (without the quotation surrounding marks):
# "  { "source": "topic-name", "target": "subscribing-consumer-group-id" },"
echo_as_source_target_javascript_object() {
  while read topic
  do
    echo "  { \"source\": \"$topic\", \"target\": \"$1\" },"
  done
}

list_subscribed_topics() {
  echo "["
  while read kafka_consumer_group_id
  do
    kafka-consumer-groups.sh \
      --bootstrap-server $KAFKA_BOOTSTRAP_SERVER \
      --group $kafka_consumer_group_id \
      --describe \
      | remove_headers | filter_topic_column | remove_duplicates \
      | echo_as_source_target_javascript_object $kafka_consumer_group_id
    done
  echo "]"
  }

list_consumer_group_ids() {
  kafka-consumer-groups.sh --bootstrap-server $KAFKA_BOOTSTRAP_SERVER --list
}


########
# Main #
########

list_consumer_group_ids  | list_subscribed_topics
