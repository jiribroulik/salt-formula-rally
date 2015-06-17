{%- from "rally/map.jinja" import benchmark with context %}
{%- if benchmark.enabled %}

include:
- git
- python

{# FIX broken PIP on Ubuntu 14 #}
rally_packages_purge:
  pkg.purged:
  - name: 'python-pip'
  - unless: "test -e /root/.rally/"

rally_pip_fix:
  cmd.run:
  - name: easy_install pip
  - require:
    - pkg: rally_packages_purge

{%- if benchmark.database.engine == "mysql" %}
{%- set pkgs = benchmark.pkgs + ["libmysqlclient-dev"] %}
{%- else %}
{%- set pkgs = benchmark.pkgs %}
{%- endif %}

rally_packages:
  pkg.installed:
  - names: {{ pkgs }}
  - require:
    - pkg: rally_packages_purge

rally_conf_dir:
  file.directory:
  - name: /etc/rally

pip_update:
  pip.installed:
    - name: pip >= 1.5.4
    - require:
      - pkg: python-pip

/srv/rally:
  virtualenv.manage:
  - system_site_packages: False
  - requirements: salt://rally/files/requirements.txt
  - require:
    - pkg: rally_packages
    - pip: pip_update

rally_db_req:
  pip.installed:
    {% if benchmark.database.engine == "mysql" %}
    - names:
      - pymysql
      - MySQL-python
    {% else %}
    - name: psycopg2
    {% endif %}
    - bin_env: /srv/rally
    - require:
      - virtualenv: /srv/rally

rally_user:
  user.present:
  - name: rally
  - system: True
  - home: /srv/rally
  - require:
    - virtualenv: /srv/rally

rally_app:
  git.latest:
  - name: {{ benchmark.source.address }}
  - target: /srv/rally/rally
  - require:
    - virtualenv: /srv/rally
    - pkg: git_packages

{#
/etc/rally/rally.conf:
  file.managed:
  - source: salt://rally/files/rally.conf
  - template: jinja
  - require:
    - virtualenv: /srv/rally
    - file: rally_conf_dir
#}

{%- set db = benchmark.database %}
rally_install:
  cmd.run:
  - name: . /srv/rally/bin/activate; ./install_rally.sh -D {{ db.engine }} --db-name {{ db.name }} --db-password {{ db.password }} --db-user {{ db.user }} --db-host {{ db.host }}
  - cwd: /srv/rally/rally
  - require:
    - git: rally_app
    - pip: pip_update
  - unless: "test -e /root/.rally/"

{%- for provider_name, provider in benchmark.get('provider', {}).iteritems() %}

/srv/rally/{{ provider_name }}.json:
  file.managed:
  - source: salt://rally/files/cloud.json
  - template: jinja
  - require:
    - file: /etc/rally/rally.conf
    - virtualenv: /srv/rally
  - defaults:
      provider_name: "{{ provider_name }}"

register_{{ provider_name }}:
  cmd.run:
  - name: . /srv/rally/bin/activate; rally deployment create --filename={{ provider_name }}.json --name={{ provider_name }}
  - cwd: /srv/rally
  - require:
    - file: /srv/rally/{{ provider_name }}.json
  - unless: "cd /srv/rally; rally deployment list | grep {{ provider_name }}"

{%- endfor %}
{%- endif %}
