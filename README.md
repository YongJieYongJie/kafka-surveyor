# Kafka Surveyor

A collection of scripts for generating a plot showing the overall Kafka cluster
topology of services deployed on a Kubernetes cluster.

![Kafka Surveyor Graph](/docs/img/screenshot-zoomed.png)


## Approach 1: Consumer-Side Topology

### Usage
1. Ensure you can connect to your Kafka cluster using the
`kafka-consumer-group.sh` script that comes with Kafka, and that thet script
is available on the system path.
1. Set the environment variable `KAFKA_BOOTSTRAP_SERVER` to the bootstrap
server for communicating with Kafka. For example, `123.12.12.123:9320`
1. Generate the consumer topology in JSON format by running the following
command from this repository's root directory in a **Linux shell**:
   ```bash
   > ./scripts/approach-1/kafka-consumer-topology.sh | tee consumer-topology.sh
   ```
1. Visualize the topology at https://yongjie.codes/kafka-surveyor.

### Explanation
This approach produces the mapping of consumer group IDs to Kafka topics
subscribed by comsumer group. It is a straightforward usage of the
`kafka-consumer-group.sh` script that comes with Kafka to query the Kafka
cluster for a list of consumer groups and the topics that each group
subscribes to.

_Note that this approach is unable to provide information on what services are
producing to which Kafka topics (see approach 2 below for that)_.


## Approach 2: Overall Topology (Java-only)
_Note: The scripts may take rather long to run as it is querying each
service sequentially_.

### Usage
1. Ensure you can connect to your Kubernetes cluster using the `kubectl`
command.
1. Ensure that you can connect to the services that you are interested in via
[JMX][jmx-link] using [Jmxterm][jmxterm-link] (see the _Explanation_ section
below for details and sample command).
1. Ensure the environment variable `JMXTERM_PATH` is set to the path to the
Uber JAR for Jmxterm.
1. Generate the overall topology in JSON format by running the following
command from this repository's root directory

   - in a **Linux shell**:
      ```bash
      > ./scripts/approach-2/kafka-producer-topology.sh |
      tee producer-topology.json
      > ./scripts/approach-2/kafka-consumer-topology.sh |
      tee consumer-topology.json
      ```

   - or in a **Windows PowerShell**:
      ```powershell
      $ .\scripts\approach-2\kafka-producer-topology.ps1 |
      Tee-Object -FilePath producer-topology.json
      $ .\scripts\approach-2\kafka-consumer-topology.ps1 |
      Tee-Object -FilePath consumer-topology.json
      ```
1. Combine the two JSON files and visualize the topology at
https://yongjie.codes/kafka-surveyor.

### Explanation
This approach produces mappings of:
 1. Service name to Kafka topics that the service is consuming from, and
 1. Service name to Kafka topics that the service is producing to,

allowing us to plot the overall topology.

_The "trick" to this approach is to realize that the official Kafka producer
and consumer clients exposes certain metrics via [JMX][jmx-link] (see
[Wikipedia article][jmx-wiki] for an overview), and by querying these
metrics, we can associate a particular service to the Kakfa topics that the
service is producing to / consuming from_.

In particular, this approach is broken down into two main steps:
 1. For each service that we are interested in, obtain the IP address (or IP
 addresses, if there may be multiple instance of each service).

     For services running on Kubernetes, the IP address may be obtained using
     a variant of the following command:
     ```bash
     > kubectl get pods --selector="app=<your-app-label-here>" \
     --output custom-columns="IP:.status.podIP"
     ```

 1. For each IP address, obtain the list of topics that the service at that
 IP address is producing to / consuming from.

    This may be achieved with [Jmxterm][jmxterm-link], using commands like
    the following:
    ```bash
    # Creating a command file so Jmxterm might be runned non-interactively.
    > echo "beans" > jmxterm-commands.in

    # Using Jmxterm to query the mbeans exposed via JMX.
    > java -jar <path-to-jmxterm-uber-jar-file> --noninteract --verbose silent \
     --url "<your-service-IP-here>:9010" --input jmxterm-commands.in

    ```
    To filter the output from the above command to only lines containing the
    Kafka topics, simply pipe it to `grep "producer-topic-metrics"` and `grep
    "consumer-fetch-manager-metrics"` to get the Kafka topcis that the
    service is producing to / consuming from respectively.

[jmx-link]: https://www.oracle.com/java/technologies/javase/javamanagement.html
[jmx-wiki]: https://en.wikipedia.org/wiki/Java_Management_Extensions
[jmxterm-link]: https://github.com/jiaqi/jmxterm


## TODO:
1. Add code and documentation for d3.js visualization.
1. Find a way to map the Kafka topology of services running in Go.
1. Visually differentiate producers, consumers, and topics on the d3.js
visualization.
