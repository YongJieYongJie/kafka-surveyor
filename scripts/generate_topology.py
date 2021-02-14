import pprint as pp
from collections import defaultdict

def parse_consumer_topic(topic_line):
  # E.g., [Subscribed Topic(s) for Consumer Group: my-consumer-group-id-0]
  return topic_line[41:-2]

def parse_consumer_trace(consumer_topology_file):
  '''Parses the output of 'scripts/trace-consumers.sh' into the following:
  {
    <consumer-group-id-0>: [
      <topic-0>,
      <topic-1>,
      ...],
    <consumer-group-id-1>: [
      <topic-0>,
      <topic-1>,
      ...],
    ...
  }
  '''

  topic_to_consumer_group = defaultdict(list)
  curr_topic = ''

  with open(consumer_topology_file, 'rt') as raw_file:
    for line in raw_file:
      if line.startswith('['):
        curr_topic = parse_consumer_topic(line)
      else:
        topic_to_consumer_group[curr_topic].append(line.strip())
  return dict(topic_to_consumer_group)

def parse_topic(topic_line):
  '''Converts a line like: [*] Searching for producers to topic: my-beautiful-topic-name
  to: my-beautiful-topic-name
  '''

  return topic_line.split(':')[1].strip()

def parse_producer_repo_name(repo_name_line):
  '''Converts a line like: [!] Found file containing MY_BEAUTIFUL_TOPIC_NAME_ENV_VAR: /path-to-my-git-repo/**/my-repo-name/**/ClassThatPublishesToMY_BEAUTIFUL_TOPIC_NAME_ENV_VAR.java
  to: my-repo-name
  '''

  repo_path = repo_name_line.split(':')[1].strip()
  #return '-'.join(repo_path.split('/')[5:7])
  return repo_path.split('/')[6]

def parse_producer_trace(in_file, out_file=None):
  '''Parses the output of 'scripts/trace-producers.sh' into the following:
  {
    <topic-0>: {
      <producer-service-0>,
      <producer-service-1>,
      ...},
    <topic-1>: {
      <producer-service-0>,
      <producer-service-1>,
      ...},
    ...
  }
  '''

  topic_to_producer_repo = defaultdict(set)
  curr_topic = ''
  all_topics = set()
  with open(in_file, 'rt') as raw_file:
    for line in raw_file:
      if 'Searching for producers to topic' in line:
        curr_topic = parse_topic(line)
        all_topics.add(curr_topic)
      elif 'Found file containing' in line:
        repo_name = parse_producer_repo_name(line)
        topic_to_producer_repo[curr_topic].add(repo_name)
  unmapped_topic = all_topics.difference(topic_to_producer_repo)
  return dict(topic_to_producer_repo), sorted(unmapped_topic)


def parse_yaml_filename(service_name_line):
  '''Converts a line like: /path-to-my-deployment-repo-with-ansible-scripts/**/my-service-name.yml
  to: my-service-name
  '''

  yaml_filename = service_name_line.rsplit('/', maxsplit=1)[1].strip()
  return yaml_filename.rsplit('.', maxsplit=1)[0]

def parse_cgid(cgid_line):
  '''Converts a line like: [*] Locating service for consumer group ID: my-consumer-group-id
  to: my-consumer-group-id
  '''
  return cgid_line.split(':')[1].strip()


def generate_cgid_to_yaml_mapping(cgid_mapping_file):
  '''Parses the output of 'scripts/get-consumer-group-to-service-mapping.sh' into the following:
  {
    <consumer-group-id-0>: [
      <consumer-service-0>,
      <consumer-service-1>,
      ...],
    <consumer-group-id-1>: [
      <consumer-service-0>,
      <consumer-service-1>,
      ...],
    ...
  }
  
  Also returns a list of unmapped consumer group IDs (i.e., where the original
  shell script was not able to locate the service belonging to the particular
  consumer group ID).
  '''
  cgid_to_yaml = defaultdict(list)
  all_cgids = set()
  curr_cgid = ''
  with open(cgid_mapping_file, 'rt') as raw_file:
    for line in raw_file:
      if 'Locating service for consumer group ID' in line:
        cgid = parse_cgid(line)
        curr_cgid = cgid
        all_cgids.add(cgid)
      else:
        yaml_filename = parse_yaml_filename(line)
        cgid_to_yaml[curr_cgid].append(yaml_filename)

  cgid_to_yaml = dict(cgid_to_yaml)
  unmapped_cgids = all_cgids.difference(cgid_to_yaml)

  return cgid_to_yaml, unmapped_cgids

def generate_producer_repo_to_consumer_yaml_mapping(topic_to_producer_repo, cgid_to_yaml):

  producer_repos = set()
  for repos_per_topic in topic_to_producer_repo.values():
    for repo in repos_per_topic:
      producer_repos.add(repo)

  consumer_yamls = set()
  for yamls in cgid_to_yaml.values():
    for yaml in yamls:
      consumer_yamls.add(yaml)

  # print('\nProducer Repos:', sorted(producer_repos))
  # print('\nConsumer YAMLs:', sorted(consumer_yamls))
  # print('\nUnmapped:', producer_repos - consumer_yamls)

  overlapping = producer_repos.intersection(consumer_yamls)
  auto_mapped = { name: name for name in overlapping }

  # manual_mapping is required to map cases where the repository folder name
  # has no corresponding yaml deployment file in the build scripts repository.
  manual_mapping = {
      'my-repo-name': 'mapping-target',
      # ...
  }
  # print('\nManually mapped:')
  # pp.pprint(manual_mapping)
  return { **auto_mapped, **manual_mapping }

def generate_dot_src(topic_to_producer_repo,
    producer_repo_to_consumer_yaml_mapping, cgid_to_topics, cgid_to_yaml,
    out_file):

  # Producer (mapped to YAML) -> Topic
  producer_lines = []
  for topic in topic_to_producer_repo:
    for producer_repo in topic_to_producer_repo[topic]:
      if producer_repo not in producer_repo_to_consumer_yaml_mapping:
        print(f'Producer repo "{producer_repo}" is not mapped to any deployment YAML file. Skipping.')
        continue
      #print(f'topic: {topic} | produce_repo: {producer_repo} | producer_repo(mapped): {producer_repo_to_consumer_yaml_mapping[producer_repo]}')
      producer_lines.append(f'"{producer_repo_to_consumer_yaml_mapping[producer_repo]}" -> "{topic}"')

  # Topic -> Consumer YAML
  consumer_lines = []
  for cgid in cgid_to_topics:
    for topic in cgid_to_topics[cgid]:
      if cgid not in cgid_to_yaml:
        print(f'Consumer group ID "{cgid}" is not mapped to any deployment YAML file. Skipping.')
        continue
      for yaml in cgid_to_yaml[cgid]:
        consumer_lines.append(f'"{topic}" -> "{yaml}"')

  # Output
  out = ['digraph D {'] + list(set(producer_lines)) + list(set(consumer_lines)) + ['}']
  dot_src = '\n'.join(out)

  if out_file:
    with open(out_file, 'wt') as dot_src_file:
      dot_src_file.write(dot_src)


def main(consumer_topology_file, producer_topology_file, cgid_mapping_file,
    out_file=None):

  cgid_to_topics = parse_consumer_trace(consumer_topology_file)
  # print('<Consumer Group ID> -> <Subscribed Topics>:')
  # pp.pprint(cgid_to_topics)

  topic_to_producer_repo, unmapped_producer_topics = parse_producer_trace(
      producer_topology_file)
  # print('\n<Topic> -> <Producer Repo Name>:')
  # pp.pprint(topic_to_producer_repo)
  print(f'\nUnmapped producer topics ({len(unmapped_producer_topics)}):')
  pp.pprint(unmapped_producer_topics)

  cgid_to_yaml, unmapped_cgids = generate_cgid_to_yaml_mapping(
      cgid_mapping_file)
  # print('\n<Consumer Group ID> -> <Deployment YAML Filenames>:')
  # pp.pprint(cgid_to_yaml)
  print(f'\nUnmapped consumer group IDs ({len(unmapped_cgids)}):')
  pp.pprint(unmapped_cgids)

  producer_repo_to_consumer_yaml_mapping = \
      generate_producer_repo_to_consumer_yaml_mapping(topic_to_producer_repo,
          cgid_to_yaml)
  # print('\n<Producer Repo Name> -> <Deployment YAML Filenames>:')
  # pp.pprint(producer_repo_to_consumer_yaml_mapping)

  generate_dot_src(topic_to_producer_repo, producer_repo_to_consumer_yaml_mapping,
      cgid_to_topics, cgid_to_yaml, out_file)


if __name__ == '__main__':

  import sys
  if not (4 <= len(sys.argv) <= 5):
    print(f'Usage:\n  {__file__} cgid_to_topics topic_to_producer_repo cgid_to_yaml [out_file]')
    exit()

  cgid_to_topics = sys.argv[1]
  topic_to_producer_repo = sys.argv[2]
  cgid_to_yaml = sys.argv[3]
  outfile = None
  if len(sys.argv) == 5:
    outfile = sys.argv[4]

  main(cgid_to_topics, topic_to_producer_repo, cgid_to_yaml, outfile)
  # e.g.:
  # main('out/consumer-topology.2021-01-01.txt',
  #     'out/producer-topology.2021-01-30.txt',
  #     'out/consumer-group-to-service-mapping.txt')

