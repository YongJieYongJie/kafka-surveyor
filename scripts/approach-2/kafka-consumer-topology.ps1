# trace-consumer-topology.ps1
#
# Synopsis:
# Herein lies a collection of poorly-written PowerShell scripts for the sole
# purpose of generating the Kafka consumer topology of services deployed on
# Kubernetes. In other words, it generates a mapping of each service deployed
# to the Kafka topic(s) that the service consumes from.
#
# Prerequisites:
# Adventurers who seek to explore these ruins would do well to hind the
# following advice:
#  - Make sure you are able to connect to your Kubernetes cluster using kubectl.
#  - Make sure you are able to connect to the application deployed on Kubernetes
#  via JMX using Jmxterm (see https://github.com/jiaqi/jmxterm).
#  - The environment variable JMXTERM_PATH is set to be pointing to the Jmxterm
#  jar file (again, see https://github.com/jiaqi/jmxterm).
#
# Details:
#  - The list of services deployment on Kubernetes is enumerate based on the
#  .metadata.labels.app label. It is assumed all pods with the same label are
#  instances of a single service.
#
# Common Issues:
# Should the brave adventurers' journey be hindered in anyway, consult the
# following:
#  - Make sure the are using the correct version of Java. Generally, the machine
#  that you are running the script on should have the same Java version as the
#  services deployed on Kubernetes.


<# Function Definitions #>

function Get-KubeApps
{
  <#
  .SYNOPSIS
  List all the apps on Kubernetes.
  #>
  Write-Verbose "Getting unique .metadata.labels.app labels from kubenetes"
  kubectl get pods --output custom-columns="APP:.metadata.labels.app" `
    | Select-Object -Skip 1 | Sort-Object | Get-Unique
}

function Get-PodIPs
{
  <#
  .SYNOPSIS
  List the IP address of every pods of a particular app on Kubernetes.
  .PARAMETER AppLabel
  The value set on .metadata.labels.app.
  .OUTPUTS
  E.g., "dp-analytics-background|10.76.60.82"
  #>
  param (
    $AppLabel
  )
  Write-Verbose "Getting IPs for all pods with .metadata.labels.app=${AppLabel}"
  kubectl get pods --selector="app=${AppLabel}" `
    --output custom-columns="IP:.status.podIP" | ConvertFrom-Csv `
    | foreach { Write-Output "$AppLabel|$($_.IP)" }
}

function Get-PodInputKafkaTopics
{
  <#
  .SYNOPSIS
  List the output Kafka topics for this particular pod.
  .PARAMETER JmxtermPath
  Path to the Jmxterm jar file (see https://github.com/jiaqi/jmxterm).
  .PARAMETER PodIP
  The IP address of the pod on Kubernetes.
  .PARAMETER AppLabel
  The app name to use in labelling the output.
  .OUTPUTS
  E.g., "epi|prod-epi-act-order-create"
  #>
  param (
    $JmxtermPath,
    $PodIP,
    $AppLabel
  )
  Write-Verbose "Getting output topic(s) for pod .status.podIP=${PodIP}"

  # Creating a temporary file with a single command "beans" to serve as input
  # file for Jmxterm.
  $ScriptFile = New-TemporaryFile
  Write-Output 'beans' | Out-File -FilePath $ScriptFile -Encoding utf8

  # Actual Jmxterm command to list the topics
  $topics = java -jar $JmxtermPath --noninteract --verbose silent `
    --url "${PodIP}:9010" --input $ScriptFile 2> $null
  
  # Only continue the piping if the previous command is successful. $? is an
  # automatic variable, set to true if previous command was successful, false
  # if otherwise.
  if ($?) {
    $topics |
      Select-String -Pattern ",topic=(.+?),type=consumer-fetch-manager-metrics" |
      foreach { $_.Matches.Groups[1].Value } |
      foreach { Write-Output "$AppLabel|$_"}
  }
}

function Get-KafkaConsumerTopology
{
  <#
  .SYNOPSIS
  Generate the consumer topology for the Kafka cluster.
  .PARAMETER JmxtermPath
  Path to the Jmxterm jar file (see https://github.com/jiaqi/jmxterm).
  .NOTES
  Before using this function, ensure that the following prerequisites are met:
   - You are able to connect to your Kubernetes cluster using kubectl
   - You are able to connect to the application deployed on Kubernetes via
   JMX using Jmxterm (see https://github.com/jiaqi/jmxterm).
  .OUTPUTS
  E.g.:
  [

    ...
  ]
  #>
  param (
    $JmxtermPath
  )

  Write-Output "["

  # Using hashtable as a set to keep track of mappings that we have already
  # seen (necessary because for each service (e.g., "core"), we are checking
  # every single pods for the output topics).
  # 
  # It is necessary to check every single pod because different pods may
  # consume from a subset of the topics that the service may consume (due to
  # Kafka topic-partition assignment).
  $AppToTopicMappings = @{}
  Get-KubeApps | Select-String -Pattern '<none>', 'mysql-exporter-' -NotMatch |
    foreach { Get-PodIPs -AppLabel $_ } |
    foreach {
      $AppLabel = $_.split('|')[0]
      $PodIP = $_.split('|')[1]
      Get-PodInputKafkaTopics -JmxtermPath $JmxtermPath -PodIP $PodIP -AppLabel $AppLabel
    } |
    foreach { 
      $AppLabel = $_.split('|')[0]
      $TopicName = $_.split('|')[1]
      $JSONLine = "  { ""source"": ""${TopicName}"", ""target"": ""${AppLabel}"" },"
      if (!$AppToTopicMappings.Contains($JSONLine)) {
        Write-Output $JSONLine
        $AppToTopicMappings[$JSONLine] = $true
      }
    }

    Write-Output "]"
}


<# Main #>

# $env:JMXTERM_PATH="C:\my-path-to\jmxtermm-<version>-uber.jar"
Write-Verbose "[*] Using Jmxterm at ""${env:JMXTERM_PATH}"" (based on environment variable JMXTERM_PATH)"
Get-KafkaConsumerTopology -JmxtermPath $env:JMXTERM_PATH


# Sample output from Jmxterm for 
# kafka.consumer:client-id=webhook-notification-streams-consumer-group-prod-1-ae9f90b6-4738-4d85-a4bd-82017ed135af-StreamThread-8-consumer,partition=14,topic=prod-parcel-evt-lost-damaged,type=consumer-fetch-manager-metrics