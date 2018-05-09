{% set knox_version = salt['pillar.get']('knox:release_version', '') %}
{% set knox_authentication = salt['pillar.get']('knox:authentication', '') %}
{% set knox_master_secret = salt['pillar.get']('knox:master_secret', '') %}

{% set knox_zip = 'knox-' + knox_version + '.zip' %}

{% set pnda_mirror = pillar['pnda_mirror']['base_url'] %}
{% set misc_packages_path = pillar['pnda_mirror']['misc_packages_path'] %}
{% set mirror_location = pnda_mirror + misc_packages_path %}
{% set namenode_host = salt['pnda.get_hosts_by_role']('HDFS', 'NAMENODE')[0] %}
{% set oozie_node = salt['pnda.get_hosts_by_role']('OOZIE', 'OOZIE_SERVER')[0] %}
{% set hive_node = salt['pnda.get_hosts_by_role']('HIVE', 'HIVE_SERVER')[0] %}
{% set pnda_domain = pillar['consul']['data_center'] + '.' + pillar['consul']['domain'] %}
{% set release_directory = pillar['pnda']['homedir'] %}

include:
  - java

consul-dep-unzip:
  pkg.installed:
    - pkgs: 
      - {{ pillar['unzip']['package-name'] }}
      - {{ pillar['expect']['package-name'] }}

knox-user-group:
  group.present:
    - name: knox
  user.present:
    - name: knox
    - gid_from_name: True
    - groups:
      - knox

knox-dl-and-extract:
  archive.extracted:
    - name: {{ release_directory }}
    - source: {{ mirror_location }}/{{ knox_zip }}
    - source_hash: {{ mirror_location }}/{{ knox_zip }}.sha
    - user: knox
    - group: knox
    - archive_format: zip
    - if_missing: {{ release_directory }}/knox-{{ knox_version }}

knox-link_release:
  file.symlink:
    - name: {{ release_directory }}/knox
    - target: {{ release_directory }}/knox-{{ knox_version }}

knox-update-permissions-scripts:
  cmd.run:
    - name: chmod +x {{ release_directory }}/knox-{{ knox_version }}/bin/*.sh
    - user: knox
    - group: knox
    - require:
      - archive: knox-dl-and-extract

{% if knox_authentication == 'internal' %}
knox-start-embedded-ldap:
  cmd.run:
    - name: {{ release_directory }}/knox-{{ knox_version }}/bin/ldap.sh start
    - user: knox
    - group: knox
    - require:
      - archive: knox-dl-and-extract

knox-master-secret-script:
  file.managed:
    - name: {{ release_directory }}/knox/bin/create-secret.sh
    - source: salt://knox/templates/create-secret.sh.tpl
    - user: knox
    - group: knox
    - mode: 755
    - template: jinja
    - context:
      knox_bin_path: {{ release_directory }}/knox/bin
    - unless: test -f {{ release_directory }}/knox/bin/create-secret.sh

knox-init-authentication:
  cmd.run:
    - name: {{ release_directory }}/knox/bin/create-secret.sh {{ knox_master_secret }}
    - user: knox
    - group: knox
    - require:
      - file: knox-master-secret-script
{% endif %}

knox-set-configuration:
  file.managed:
    - name: {{ release_directory }}/knox-{{ knox_version }}/conf/topologies/pnda.xml
    - source: salt://knox/templates/pnda.xml.tpl
    - template: jinja
    - context:
      knox_authentication: {{ knox_authentication }}
      namenode_host: {{ namenode_host }}
      oozie_node: {{ oozie_node }}
      hive_node: {{ hive_node }}
      pnda_domain: {{ pnda_domain }}
    - require:
      - cmd: knox-init-authentication

{% set knox_dm_dir = release_directory + '/knox/data/services/pnda-deployment-manager/1.0.0/' %}

knox-dm_dir:
  file.directory:
    - name: {{ knox_dm_dir }}
    - makedirs: True

knox-dm_service:
  file.managed:
    - name: {{ knox_dm_dir }}/service.xml
    - source: salt://knox/files/dm_service.xml
    - require:
      - file: knox-dm_dir

knox-dm_rewrite:
  file.managed:
    - name: {{ knox_dm_dir }}/rewrite.xml
    - source: salt://knox/files/dm_rewrite.xml
    - require:
      - file: knox-dm_dir

knox-start-gateway:
  cmd.run:
    - name: {{ release_directory }}/knox-{{ knox_version }}/bin/gateway.sh start
    - user: knox
    - require:
      - cmd: knox-init-authentication
      - file: knox-dm_service
      - file: knox-dm_rewrite