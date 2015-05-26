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

```
TBD
```

### Command Line Options

```
    -e, --environment  within config.yaml
Redis overrides
    -H, --redis-host   string
    -p, --redis-port   number
    -d, --redis-db     number
Git repo overrides
    -r, --git-repo     path/to/repo_dir
    -b, --git-branch   e.g. master
Other options
    -D, --dump         Just dump Redis contents
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

1. Connect to redis according to specified redis options
2. `GET foo:bar:baz:md5`; *Assume md5 mismatch*
3. `SET foo:bar:baz` to the file contents
4. `SET foo:bar:baz:md5` to the file contents' md5
5. `INCR foo:bar:baz:version`

### Execution

This script is short-running and intended to be scheduled by e.g. `cron`
