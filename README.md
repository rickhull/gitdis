# gitdis

## Install

### Prerequisites

* Ruby (>= 2.0)

### Procedure

`gem install gitdis`

## Usage

`gitdis path/to/config.yaml [options]`

## Config

### YAML Config

Toplevel keys are environments.  `default` is required. Other environment
settings override defaults.  5 options, 1 keymap.

```
default:
  redis-host: localhost
  redis-port: 6379
  redis-db: 0
  git-repo: ~/foo/bar/baz
  git-branch: quux
  keymap:
    "redis:key:1": "path/to/file1"
    "redis:key:2": "path/to/file2"

qa:
  redis-host: qa.big.com
  git-branch: develop

prod:
  redis-host: secret.big.net
  git-branch: master
```

### Command Line Options

Select your environment (optional).  Add final overrides (optional).

```
  Environment selection
    -e, --environment  select within YAML[environments]
  Redis overrides
    -H, --redis-host   string
    -p, --redis-port   number
    -d, --redis-db     number
  Git repo overrides
    -r, --git-repo     path/to/repo_dir
    -b, --git-branch   e.g. master
  Other options
    -D, --dump         Just dump Redis contents per YAML keymap
    -h, --help
```

### Basic operation

1. pull the latest changes from origin on the specified branch
2. iterate over all the expected filenames, skipping any that are missing
3. calculate md5 for all the filenames
4. compare the md5 to what is in redis
5. update redis if the md5s do not match

### Redis update

Assuming `foo:bar:baz` base key:

```
# redis.connect(redis_options)
GET foo:bar:baz:md5 # assume md5 mismatch
SET foo:bar:baz     # file contents
SET foo:bar:baz:md5 # file contents md5
INCR foo:bar:baz:version
```

### Execution

This script is short-running and intended to be scheduled by e.g. `cron`
